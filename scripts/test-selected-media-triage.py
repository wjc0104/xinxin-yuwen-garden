"""Offline trust-boundary checks using synthetic bytes and fake transports/processes only."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch
from urllib.request import Request

spec = importlib.util.spec_from_file_location("triage", Path(__file__).with_name("triage-selected-media.py"))
triage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(triage)
URL = "https://example.bilivideo.com/private?token=NEVER_EXPORT"
LAUNCH = "12345678-1234-1234-1234-123456789012"


class Response(io.BytesIO):
    def __init__(self, data=b"abcd", status=206, headers=None, url=URL):
        super().__init__(data)
        self.status, self.headers, self.url = status, headers or {"Content-Range": "bytes 0-3/4"}, url

    def geturl(self):
        return self.url


class Opener:
    def __init__(self, response):
        self.response, self.requests = response, []

    def open(self, request, timeout):
        self.requests.append((request, timeout))
        return self.response


class TriageChecks(unittest.TestCase):
    def fixture(self, root):
        cache = root / "app/Library/Caches"
        samples = cache / "same-item-render"
        samples.mkdir(parents=True)
        locator = {"schema": 1, "generation": 1, "launch": LAUNCH, "identityNamespace": triage.NAMESPACE, "url": URL}
        (cache / triage.LOCATOR).write_text(json.dumps(locator))
        row = {"generation": 1, "launch": LAUNCH, "sequence": 1, "identityNamespace": triage.NAMESPACE,
               "bufferCopied": True, "currentTime": {"seconds": 25},
               "itemTimeForDisplay": {"value": 345600, "timescale": 16000, "epoch": 0, "flags": 1}}
        sample = samples / "g1-s1.json"
        sample.write_text(json.dumps(row))
        return cache, locator, sample, row

    def test_locator_policy_and_generation_linkage_use_returned_pts(self):
        for url in ["http://x.bilivideo.com/a", "https://u:p@x.bilivideo.com/a", "https://bilivideo.com.evil/a",
                    "https://other.com/a", "https://x.bilivideo.com:444/a", URL + "\n"]:
            self.assertFalse(triage.approved_url(url))
        self.assertTrue(triage.approved_url(URL))
        with tempfile.TemporaryDirectory() as temporary:
            cache, locator, sample, row = self.fixture(Path(temporary))
            generation, targets = triage.targets(cache, locator)
            self.assertEqual((generation, targets[0]["targetPTS"]), (1, 21.6))
            row["launch"] = "00000000-0000-0000-0000-000000000000"
            sample.write_text(json.dumps(row))
            with self.assertRaisesRegex(triage.Inconclusive, "linkage"):
                triage.targets(cache, locator)
            (cache / triage.LOCATOR).write_bytes(b"x" * 16385)
            with self.assertRaisesRegex(triage.Inconclusive, "metadata"):
                triage.bounded_json(cache / triage.LOCATOR, cache, 16384)

    def test_one_fetch_hash_range_size_deadline_and_credential_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "private.mp4"
            opener = Opener(Response())
            result = triage.fetch(URL, destination, opener)
            self.assertEqual(result["bytes"], 4)
            self.assertEqual(result["sha256"], triage.hashlib.sha256(b"abcd").hexdigest())
            self.assertEqual(len(opener.requests), 1)
            request, timeout = opener.requests[0]
            self.assertEqual(request.get_header("Range"), f"bytes=0-{triage.CAP - 1}")
            self.assertEqual(timeout, 5)
            unknown_length = triage.fetch(URL, destination, Opener(Response(status=200, headers={"Content-Type": "video/mp4"})))
            declared_length = triage.fetch(URL, destination, Opener(Response(status=200, headers={"Content-Length": "4"})))
            self.assertFalse(unknown_length["completeObject"])
            self.assertTrue(declared_length["completeObject"])
            self.assertEqual(unknown_length["sha256"], result["sha256"])
            for response in [Response(headers={"Content-Range": "bytes 1-4/5"}),
                             Response(headers={"Content-Range": "bytes 0-2/4"}),
                             Response(headers={"Content-Range": "bytes 0-3/4", "Content-Length": "5"}),
                             Response(data=b"abc"), Response(status=401),
                             Response(url="http://example.bilivideo.com/a"),
                             Response(headers={"Set-Cookie": "NEVER_EXPORT"}),
                             Response(headers={"Content-Encoding": "gzip"})]:
                with self.assertRaises(triage.Inconclusive):
                    triage.fetch(URL, destination, Opener(response))
            with patch.object(triage, "CAP", 4), self.assertRaisesRegex(triage.Inconclusive, "size"):
                triage.fetch(URL, destination, Opener(Response(b"abcde", status=200, headers={"Content-Type": "video/mp4"})))
            with patch.object(triage.time, "monotonic", side_effect=[0, 36]), self.assertRaisesRegex(triage.Inconclusive, "deadline"):
                triage.fetch(URL, destination, Opener(Response()))

    def test_redirect_hops_revalidate_url_and_never_accept_credentials(self):
        redirect = triage.Redirects(triage.time.monotonic() + 30)
        request = Request(URL, headers=triage.HEADERS)
        next_request = redirect.redirect_request(request, None, 302, "", {}, "https://bilivideo.com/next")
        self.assertEqual(next_request.get_header("Referer"), triage.HEADERS["Referer"])
        for url in ["http://bilivideo.com/a", "https://evil.com/a", "https://u:p@bilivideo.com/a"]:
            with self.assertRaises(triage.Inconclusive):
                triage.Redirects(triage.time.monotonic() + 30).redirect_request(request, None, 302, "", {}, url)
        with self.assertRaisesRegex(triage.Inconclusive, "credentials"):
            triage.Redirects(triage.time.monotonic() + 30).redirect_request(request, None, 302, "", {"Set-Cookie": "secret"}, URL)
        redirect.hops = 3
        with self.assertRaisesRegex(triage.Inconclusive, "redirect_limit"):
            redirect.redirect_request(request, None, 302, "", {}, URL)

    def test_app_container_path_validation_and_symlink_cleanup_rejection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            base = root / "Library/Developer/CoreSimulator/Devices"
            container = base / LAUNCH / "data/Containers/Data/Application" / LAUNCH
            (container / "Library/Caches").mkdir(parents=True)
            completed = subprocess.CompletedProcess([], 0, str(container), "NEVER_EXPORT")
            with patch.object(triage.Path, "home", return_value=root), patch.object(triage.subprocess, "run", return_value=completed):
                self.assertEqual(triage.container_cache(LAUNCH), container / "Library/Caches")
                completed.stdout = str(root / "foreign")
                with self.assertRaises(triage.Inconclusive):
                    triage.container_cache(LAUNCH)
            with self.assertRaises(triage.Inconclusive):
                triage.cleanup_private(root, root)
            private = root / "selected-media-private-owned"
            private.mkdir()
            (private / "prefix.mp4").write_bytes(b"secret")
            triage.cleanup_private(private, root)
            self.assertFalse(private.exists())
            symlink = root / "selected-media-private-link"
            try:
                symlink.symlink_to(container, target_is_directory=True)
            except OSError:
                return  # Windows may deny unprivileged symlink creation.
            with self.assertRaises(triage.Inconclusive):
                triage.cleanup_private(symlink, root)
            self.assertTrue(container.exists())

    def test_software_sequential_decode_actual_pts_export_and_metadata_allowlist(self):
        with tempfile.TemporaryDirectory() as temporary:
            private = Path(temporary)
            commands = []
            def fake_process(command, directory, stem):
                commands.append(command)
                path = directory / (stem + ".json")
                if stem == "probe":
                    path.write_text(json.dumps({"streams": [{"codec_name": "h264", "width": 1280, "height": 720, "tags": {"url": URL}}],
                                                "frames": [{"pts": 0, "pts_time": "0", "pict_type": "I"},
                                                           {"pts": 345600, "pts_time": "21.6", "pict_type": "B"}]}))
                else:
                    (directory / "frame-1.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + struct.pack(">II", 1280, 720))
                return path
            requested = [{"sequence": 4, "targetPTS": 21.6, "targetValue": 345600, "targetTimescale": 16000}]
            with patch.object(triage.shutil, "which", side_effect=lambda value: value), patch.object(triage, "private_process", side_effect=fake_process):
                result, images = triage.decode(private / "prefix.mp4", private, requested)
                self.assertEqual(result["frames"][0]["actualPTS"], 21.6)
                self.assertEqual(result["frames"][0]["ptsDifference"], 0)
                self.assertEqual(result["frames"][0]["pict_type"], "B")
                self.assertEqual(len(images), 1)
                self.assertNotIn("NEVER_EXPORT", json.dumps(result))
                self.assertIn("%+31", commands[0])
                self.assertNotIn("-codec_whitelist", commands[0])
                self.assertIn("none", commands[1])
                self.assertIn("h264", commands[1])
                self.assertIn("-copyts", commands[1])
                self.assertNotIn("-ss", commands[0] + commands[1])
                with self.assertRaisesRegex(triage.Inconclusive, "target_frame"):
                    triage.decode(private / "prefix.mp4", private, [{"targetPTS": 10}])
            with patch.object(triage.shutil, "which", return_value=None), self.assertRaisesRegex(triage.Inconclusive, "tools"):
                triage.decode(private / "prefix.mp4", private, requested)

    @unittest.skipUnless(triage.shutil.which("ffprobe") and triage.shutil.which("ffmpeg"),
                         "Local ffprobe/FFmpeg pair unavailable; synthetic A/V tool compatibility unverified")
    def test_real_local_h264_aac_command_path(self):
        with tempfile.TemporaryDirectory() as temporary:
            private = Path(temporary)
            prefix = private / "synthetic.mp4"
            completed = subprocess.run([triage.shutil.which("ffmpeg"), "-nostdin", "-v", "error",
                                        "-f", "lavfi", "-i", "color=c=blue:s=160x90:r=10",
                                        "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono", "-t", "1",
                                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
                                        "-movflags", "+faststart", str(prefix)],
                                       capture_output=True, timeout=35, check=False)
            self.assertEqual(completed.returncode, 0, "Synthetic H264+AAC generation failed; raw stderr kept private")
            self.assertFalse(bool(completed.stderr), "Synthetic generator emitted stderr; raw content kept private")
            result, images = triage.decode(prefix, private, [{"sequence": 1, "targetPTS": 0.5,
                                                             "targetValue": 5, "targetTimescale": 10}])
            self.assertEqual(result["stream"]["codec_name"], "h264")
            self.assertLessEqual(abs(result["frames"][0]["ptsDifference"]), 0.1)
            self.assertEqual(len(images), 1)

    def test_failure_cleans_locator_and_prefix_and_exports_only_safe_report(self):
        for failure in ["fetch", "decode", "success"]:
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                cache, _, _, _ = self.fixture(root)
                runner = root / "runner"
                runner.mkdir()
                stale = root / "build/selected-media-triage"
                stale.mkdir(parents=True)
                (stale / "report.json").write_text("STALE_NEVER_UPLOAD")
                (stale / "frame-1.png").write_bytes(b"STALE_NEVER_UPLOAD")
                (stale / "frame-2.png").write_bytes(b"x" * (triage.PNG_CAP + 1))
                (stale / "frame-3.png").mkdir()
                (stale / "frame-4.png").mkdir()
                def fake_fetch(url, prefix):
                    prefix.write_bytes(b"PRIVATE_MEDIA_NEVER_EXPORT")
                    if failure == "fetch":
                        raise RuntimeError(URL)
                    return {"bytes": 25, "sha256": "a" * 64}
                def fake_decode(prefix, private, targets):
                    if failure == "decode":
                        raise triage.Inconclusive("decode_incomplete_or_unsupported")
                    image = private / "frame-1.png"
                    image.write_bytes(b"synthetic_png")
                    return {"frames": [{"targetPTS": 21.6, "actualPTS": 21.6, "png": image.name}]}, [image]
                old = Path.cwd()
                try:
                    os.chdir(root)
                    with patch.dict(os.environ, {"SAME_ITEM_RENDER_DIAGNOSTICS": "true", "RUNNER_TEMP": str(runner),
                                                 "GITHUB_OUTPUT": str(root / "github-output")}), \
                         patch.object(triage, "container_cache", return_value=cache), \
                         patch.object(triage, "fetch", side_effect=fake_fetch), \
                         patch.object(triage, "decode", side_effect=fake_decode), redirect_stdout(io.StringIO()) as console:
                        self.assertEqual(triage.main(), 0)
                    exports = [line for line in (root / "github-output").read_text().splitlines() if line.startswith("build/")]
                    destination = (root / exports[0]).parent
                    report = json.loads((destination / "report.json").read_text())
                    self.assertEqual(report["status"], "DECODED_SAME_LOCATOR_TRIAGE" if failure == "success" else "INCONCLUSIVE")
                    self.assertTrue(report["cleanupVerified"])
                    self.assertFalse(report["priorBytesEqualityEstablished"])
                    self.assertFalse((cache / triage.LOCATOR).exists())
                    self.assertEqual(list(runner.iterdir()), [])
                    names = {p.name for p in destination.iterdir()}
                    self.assertEqual(names, {"report.json", "frame-1.png"} if failure == "success" else {"report.json"})
                    self.assertEqual({(root / name).name for name in exports}, names)
                    self.assertEqual(len({(root / name).parent for name in exports}), 1)
                    self.assertNotEqual(destination, stale)
                    self.assertEqual((stale / "report.json").read_text(), "STALE_NEVER_UPLOAD")
                    self.assertNotIn("NEVER_EXPORT", (destination / "report.json").read_text() + console.getvalue())
                    self.assertNotIn(str(root), console.getvalue())
                finally:
                    os.chdir(old)

    def test_output_directories_and_symlinks_never_publish_stale_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            old = Path.cwd()
            try:
                os.chdir(root)
                stale = root / "build/selected-media-triage"
                stale.mkdir(parents=True)
                # Fixed old report leaf is a directory, not an output file to replace/delete.
                (stale / "report.json").mkdir()
                target = root / "do-not-touch"
                target.write_text("PRIVATE_NEVER_UPLOAD")
                try:
                    (stale / "frame-1.png").symlink_to(target)
                except OSError:
                    self.skipTest("Unprivileged symlink creation unavailable")
                with patch.dict(os.environ, {"GITHUB_OUTPUT": str(root / "github-output")}):
                    fresh = triage.fresh_export_directory()
                    triage.publish_artifacts(fresh, {"status": "INCONCLUSIVE"}, [])
                published = (root / "github-output").read_text()
                self.assertIn(fresh.relative_to(root).as_posix() + "/report.json", published)
                self.assertNotIn("frame-1.png", published)
                self.assertEqual(target.read_text(), "PRIVATE_NEVER_UPLOAD")
                # A symlinked export root must yield no fresh directory and no output registration.
                foreign = root / "foreign"
                foreign.mkdir()
                linked = root / "linked"
                linked.mkdir()
                (linked / "build").symlink_to(foreign, target_is_directory=True)
                os.chdir(linked)
                with self.assertRaises(triage.Inconclusive):
                    triage.fresh_export_directory()
                self.assertEqual(list(foreign.iterdir()), [])
                self.assertFalse((linked / "github-output").exists())
            finally:
                os.chdir(old)

    def test_private_subprocess_stderr_rejection_and_deadline_kill(self):
        class Child:
            def __init__(self, command, stdout, stderr, stdin):
                self.returncode = None if command == ["hang"] else 0
                self.killed = False
                stdout.write(b"{}")
                stderr.write(b"NEVER_EXPORT private decoder description" if command == ["error"] else b"")
                stdout.flush()
                stderr.flush()
                children.append(self)

            def __enter__(self):
                return self

            def __exit__(self, *args):
                return False

            def poll(self):
                return self.returncode

            def kill(self):
                self.killed = True
                self.returncode = -9

            def wait(self, timeout=None):
                return self.returncode

        children = []
        with tempfile.TemporaryDirectory() as temporary, patch.object(triage.subprocess, "Popen", Child):
            private = Path(temporary)
            with self.assertRaisesRegex(triage.Inconclusive, "decode_incomplete_or_unsupported") as error:
                triage.private_process(["error"], private, "probe")
            self.assertNotIn("NEVER_EXPORT", str(error.exception))
            with patch.object(triage.time, "monotonic", side_effect=[0, 36]), self.assertRaisesRegex(triage.Inconclusive, "decode_deadline"):
                triage.private_process(["hang"], private, "decode")
            self.assertTrue(children[-1].killed)


if __name__ == "__main__":
    unittest.main()
