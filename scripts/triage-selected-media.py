"""Explicit CI-only same-locator triage. Never print private inputs or subprocess output."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import tempfile
import time
from urllib.parse import urlparse
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener

LOCATOR = "selected-media-private.json"
NAMESPACE = "same-item-render-launch-local"
CAP = 32 * 1024 * 1024
PNG_CAP = 4 * 1024 * 1024
BUNDLE = "com.wm0104.xinxingarden"
HEADERS = {"User-Agent": "Mozilla/5.0", "Referer": "https://www.bilibili.com/", "Range": f"bytes=0-{CAP - 1}"}
LIMITATION = "same_locator_new_fetch_not_prior_AVFoundation_bytes"


class Inconclusive(Exception):
    pass


def require(condition, code):
    if not condition:
        raise Inconclusive(code)


def approved_url(value):
    try:
        parsed = urlparse(value)
        host = parsed.hostname or ""
        return (isinstance(value, str) and len(value) <= 12000 and
                parsed.scheme == "https" and parsed.username is None and parsed.password is None and
                parsed.port in (None, 443) and not parsed.fragment and
                not any(ord(c) < 33 or ord(c) == 127 for c in value) and
                (host == "bilivideo.com" or host.endswith(".bilivideo.com") or
                 host == "upos-hz-mirrorakam.akamaized.net"))
    except (ValueError, TypeError, AttributeError):
        return False


class Redirects(HTTPRedirectHandler):
    def __init__(self, deadline):
        self.deadline, self.hops = deadline, 0

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        self.hops += 1
        require(self.hops <= 3 and time.monotonic() < self.deadline, "redirect_limit")
        require(approved_url(newurl), "redirect_rejected")
        require(not headers.get("Set-Cookie") and not headers.get("WWW-Authenticate"), "credentials_rejected")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def safe_path(path, root):
    """Reject symlink components, including missing final files used for safe cleanup."""
    path, root = Path(path).absolute(), Path(root).absolute()
    require(path.is_relative_to(root) and path != root, "unsafe_path")
    for component in [path, *path.parents]:
        require(not component.is_symlink(), "unsafe_path")
    return path


def bounded_json(path, root, limit):
    path = safe_path(path, root)
    require(path.is_file() and path.stat().st_size <= limit, "metadata_unavailable")
    with path.open("rb") as stream:
        raw = stream.read(limit + 1)
    require(len(raw) <= limit, "metadata_limit")
    return json.loads(raw)


def targets(cache, locator):
    require(set(locator) == {"schema", "generation", "launch", "identityNamespace", "url"}, "locator_schema")
    generation, launch = locator["generation"], locator["launch"]
    require(locator["schema"] == 1 and type(generation) is int and 1 <= generation <= 999999 and
            locator["identityNamespace"] == NAMESPACE and isinstance(launch, str) and
            re.fullmatch(r"[0-9A-Fa-f-]{36}", launch) is not None and approved_url(locator["url"]), "locator_rejected")
    directory = safe_path(cache / "same-item-render", cache)
    require(directory.is_dir(), "samples_unavailable")
    result = []
    for sequence in range(1, 9):
        path = directory / f"g{generation}-s{sequence}.json"
        if not path.exists():
            continue
        row = bounded_json(path, cache, 8192)
        require(row.get("launch") == launch and row.get("generation") == generation and
                row.get("sequence") == sequence and row.get("identityNamespace") == NAMESPACE,
                "sample_linkage_rejected")
        if row.get("bufferCopied") is not True:
            continue
        pts = row.get("itemTimeForDisplay", {})
        value, scale = pts.get("value"), pts.get("timescale")
        require(type(value) is int and type(scale) is int and scale > 0 and
                pts.get("epoch") == 0 and type(pts.get("flags")) is int and pts["flags"] & 1 and
                not pts["flags"] & (4 | 8 | 16), "returned_pts_invalid")
        seconds = value / scale
        if 0 <= seconds <= 30 and all(abs(seconds - r["targetPTS"]) > 1e-9 for r in result):
            result.append({"sequence": sequence, "targetPTS": seconds, "targetValue": value, "targetTimescale": scale})
    require(bool(result), "returned_pts_unavailable")
    return generation, result[:4]


def fetch(url, path, opener=None):
    require(approved_url(url), "locator_rejected")
    deadline = time.monotonic() + 35
    if opener is None:
        # No environment proxy or cookie handler; only the original public request headers.
        opener = build_opener(ProxyHandler({}), Redirects(deadline))
    digest, count = hashlib.sha256(), 0
    with opener.open(Request(url, headers=HEADERS), timeout=5) as response:
        require(time.monotonic() < deadline, "network_deadline")
        require(approved_url(response.geturl()), "redirect_rejected")
        require(not response.headers.get("Set-Cookie") and not response.headers.get("WWW-Authenticate"), "credentials_rejected")
        require(response.headers.get("Content-Encoding", "identity").lower() == "identity", "encoding_rejected")
        status, expected, total = response.status, None, None
        if status == 206:
            match = re.fullmatch(r"bytes 0-([0-9]+)/([0-9]+)", response.headers.get("Content-Range", ""))
            require(match is not None, "range_rejected")
            end, total = map(int, match.groups())
            require(0 <= end < total and end < CAP and end == min(CAP, total) - 1, "range_rejected")
            expected = end + 1
        elif status == 200:
            require(response.headers.get("Content-Range") is None, "range_rejected")
        else:
            raise Inconclusive("http_rejected")
        length = response.headers.get("Content-Length")
        if length is not None:
            require(length.isdigit() and 0 < int(length) <= CAP, "response_size_rejected")
            require(expected is None or int(length) == expected, "range_rejected")
            expected = int(length)
        with path.open("wb") as output:
            while True:
                require(time.monotonic() < deadline, "network_deadline")
                chunk = response.read1(min(64 * 1024, CAP - count + 1))
                require(time.monotonic() < deadline, "network_deadline")
                if not chunk:
                    break
                count += len(chunk)
                require(count <= CAP, "response_size_rejected")
                output.write(chunk)
                digest.update(chunk)
        require(count > 0 and (expected is None or count == expected), "incomplete_transfer")
        return {"bytes": count, "sha256": digest.hexdigest(), "httpStatus": status,
                "rangeStart": 0, "rangeEnd": count - 1, "objectBytes": total,
                "completeObject": count == total if total is not None else status == 200}


def private_process(command, private, stem):
    out, err = private / (stem + ".json"), private / (stem + ".stderr")
    deadline = time.monotonic() + 35
    with out.open("wb") as stdout, err.open("wb") as stderr:
        with subprocess.Popen(command, stdout=stdout, stderr=stderr, stdin=subprocess.DEVNULL) as child:
            try:
                while child.poll() is None:
                    require(time.monotonic() < deadline, "decode_deadline")
                    require(out.stat().st_size <= 4 * 1024 * 1024 and err.stat().st_size <= 1024 * 1024,
                            "decode_output_limit")
                    try:
                        child.wait(timeout=0.1)
                    except subprocess.TimeoutExpired:
                        pass
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait()
    require(out.stat().st_size <= 4 * 1024 * 1024 and err.stat().st_size <= 1024 * 1024, "decode_output_limit")
    require(child.returncode == 0 and err.stat().st_size == 0, "decode_incomplete_or_unsupported")
    return out


def safe_fields(row):
    result = {}
    for key in ("codec_name", "profile", "pix_fmt", "pict_type", "color_range", "color_space", "color_primaries", "color_transfer", "time_base"):
        value = row.get(key)
        if isinstance(value, str) and re.fullmatch(r"[A-Za-z0-9_./ -]{1,48}", value):
            result[key] = value
    for key in ("width", "height"):
        value = row.get(key)
        if type(value) is int and 0 < value <= 8192:
            result[key] = value
    return result


def decode(prefix, private, requested):
    probe, decoder = shutil.which("ffprobe"), shutil.which("ffmpeg")
    require(bool(probe and decoder), "software_tools_unavailable")
    entries = "stream=codec_name,profile,pix_fmt,width,height,time_base,color_range,color_space,color_primaries,color_transfer:frame=pts,pts_time,pict_type,width,height,pix_fmt,color_range,color_space,color_primaries,color_transfer"
    # Omitted interval start means decode from beginning; no seeking or timestamp rewriting.
    metadata = private_process([probe, "-v", "error", "-codec_whitelist", "h264", "-err_detect", "explode", "-select_streams", "v:0",
                                "-read_intervals", "%+31", "-show_frames", "-show_streams", "-show_entries", entries,
                                "-of", "json", str(prefix)], private, "probe")
    data = bounded_json(metadata, private, 4 * 1024 * 1024)
    streams, frames = data.get("streams", []), data.get("frames", [])
    require(len(streams) == 1 and 0 < len(frames) <= 10000, "decode_metadata_unavailable")
    stream = safe_fields(streams[0])
    require(stream.get("codec_name") == "h264" and 0 < stream.get("width", 0) <= 1920 and
            0 < stream.get("height", 0) <= 1080, "decode_capability_or_dimension_limit")
    timeline = []
    for index, frame in enumerate(frames):
        pts = float(frame.get("pts_time", "nan"))
        require(math.isfinite(pts) and (not timeline or pts >= timeline[-1][1]), "original_pts_unavailable")
        timeline.append((index, pts, frame))
    selected = []
    for row in requested:
        index, pts, frame = min(timeline, key=lambda x: abs(x[1] - row["targetPTS"]))
        require(abs(pts - row["targetPTS"]) <= 0.1, "target_frame_unavailable")
        selected.append({**row, "frameIndex": index, "actualPTS": pts, "ptsDifference": pts - row["targetPTS"],
                         "originalPTS": int(frame["pts"]), **safe_fields(frame)})
    indices = sorted({row["frameIndex"] for row in selected})
    expression = "+".join(f"eq(n\\,{index})" for index in indices)
    private_process([decoder, "-nostdin", "-v", "error", "-hwaccel", "none", "-c:v", "h264", "-err_detect", "explode", "-copyts",
                     "-i", str(prefix), "-an", "-sn", "-dn", "-map", "0:v:0", "-vf", "select=" + expression,
                     "-fps_mode", "passthrough", "-frames:v", str(len(indices)), "-c:v", "png", "-fs", str(PNG_CAP),
                     str(private / "frame-%d.png")], private, "decode")
    images = []
    for ordinal, index in enumerate(indices, 1):
        path = safe_path(private / f"frame-{ordinal}.png", private)
        require(path.is_file() and 24 <= path.stat().st_size <= PNG_CAP, "png_size_or_decode_limit")
        header = path.read_bytes()[:24]
        require(header[:8] == b"\x89PNG\r\n\x1a\n" and header[12:16] == b"IHDR", "png_invalid")
        width, height = struct.unpack(">II", header[16:24])
        require(0 < width <= 1920 and 0 < height <= 1080, "png_dimension_limit")
        name = path.name
        for row in selected:
            if row["frameIndex"] == index:
                row["png"] = name
        images.append(path)
    return {"stream": stream, "frames": selected}, images


def container_cache(simulator):
    require(re.fullmatch(r"[0-9A-Fa-f-]{36}", simulator or "") is not None, "simulator_unavailable")
    result = subprocess.run(["xcrun", "simctl", "get_app_container", simulator, BUNDLE, "data"],
                            capture_output=True, text=True, timeout=20, check=False)
    require(result.returncode == 0 and len(result.stdout) <= 4096, "container_unavailable")
    base = Path.home() / "Library/Developer/CoreSimulator/Devices"
    container = safe_path(Path(result.stdout.strip()), base)
    relative = container.relative_to(base).parts
    require(len(relative) == 6 and relative[0].lower() == simulator.lower() and
            relative[1:5] == ("data", "Containers", "Data", "Application") and
            re.fullmatch(r"[0-9A-Fa-f-]{36}", relative[5]) is not None and container.is_dir(), "container_rejected")
    cache = safe_path(container / "Library/Caches", container)
    require(cache.is_dir(), "container_unavailable")
    return cache


def cleanup_private(private, runner):
    if private is not None:
        private = safe_path(private, runner)
        require(private.parent == runner and private.name.startswith("selected-media-private-"), "cleanup_rejected")
        shutil.rmtree(private)


def main():
    if os.environ.get("SAME_ITEM_RENDER_DIAGNOSTICS") != "true":
        return 0
    report = {"schema": 1, "status": "INCONCLUSIVE", "reason": "unavailable", "limitation": LIMITATION,
              "priorBytesEqualityEstablished": False, "softwareDecodeFromBeginning": True, "cleanupVerified": False}
    private = locator_path = runner = None
    images = []
    try:
        runner = Path(os.environ["RUNNER_TEMP"]).absolute()
        require(runner.is_dir() and not runner.is_symlink() and runner.resolve() == runner, "private_root_rejected")
        cache = container_cache(os.environ.get("SIMULATOR_ID"))
        locator_path = safe_path(cache / LOCATOR, cache)
        locator = bounded_json(locator_path, cache, 16384)
        generation, requested = targets(cache, locator)
        report["generation"] = generation
        private = Path(tempfile.mkdtemp(prefix="selected-media-private-", dir=runner))
        prefix = private / "prefix.mp4"
        report["prefix"] = fetch(locator["url"], prefix)
        decoded, images = decode(prefix, private, requested)
        report.update(decoded, status="DECODED_SAME_LOCATOR_TRIAGE", reason="bounded_frames_available")
        output = safe_path(Path("build/selected-media-triage").absolute(), Path.cwd())
        output.mkdir(parents=True, exist_ok=True)
        require(not any(output.iterdir()), "export_directory_not_empty")
        for image in images:
            shutil.copyfile(image, output / image.name)
    except Inconclusive as error:
        report.update(status="INCONCLUSIVE", reason=error.args[0])
    except Exception:
        # URLs, headers, paths, decoder text and exception messages are never public evidence.
        report.update(status="INCONCLUSIVE", reason="private_operation_failed")
    finally:
        try:
            if locator_path is not None:
                safe_path(locator_path, locator_path.parent).unlink(missing_ok=True)
            cleanup_private(private, runner)
            report["cleanupVerified"] = locator_path is not None
        except Exception:
            report.update(status="INCONCLUSIVE", reason="cleanup_unverified")
        try:
            output = safe_path(Path("build/selected-media-triage").absolute(), Path.cwd())
            output.mkdir(parents=True, exist_ok=True)
            # Only our fixed report/PNG names are uploaded; never private files or raw process output.
            (safe_path(output / "report.json", Path.cwd())).write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        except Exception:
            pass
    print("SELECTED_MEDIA_TRIAGE " + report["status"] + " " + report["reason"])
    return 0  # Diagnostic availability can never replace the original XCTest result.


if __name__ == "__main__":
    raise SystemExit(main())
