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
            cache, locator, sample, row = self.fixture(Path(temporary).resolve())
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
            destination = Path(temporary).resolve() / "private.mp4"
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
            with patch.object(triage.time, "monotonic", side_effect=[0, 36, 36]), self.assertRaisesRegex(triage.Inconclusive, "deadline"):
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

    def test_transfer_progress_counts_read_and_written_bytes_on_all_exits(self):
        cases = [
            ("success", [b"abcd", b""], [0, 1, 2, 3, 4, 5, 6], None, "complete", 4, 4),
            ("before_body_deadline", [], [0, 1, 36, 36], "network_deadline", "reading_body", 0, 0),
            ("read_crosses_deadline", [b"abcd"], [0, 1, 2, 36, 36], "network_deadline", "reading_body", 4, 0),
            ("after_chunk_deadline", [b"ab"], [0, 1, 2, 3, 36, 36], "network_deadline", "reading_body", 2, 2),
            ("socket_failure", [TimeoutError("NEVER_EXPORT")], [0, 1, 2, 5], "socket", "reading_body", 0, 0),
            ("partial_socket_failure", [b"ab", TimeoutError("NEVER_EXPORT")], [0, 1, 2, 3, 4, 8],
             "socket", "reading_body", 2, 2),
            ("incomplete", [b"abc", b""], [0, 1, 2, 3, 4, 5, 6], "incomplete_transfer", "reading_body", 3, 3),
        ]
        for name, reads, ticks, reason, stage, received, written in cases:
            with self.subTest(case=name), tempfile.TemporaryDirectory() as temporary:
                destination = Path(temporary).resolve() / "private.mp4"
                response, progress = Response(), {"NEVER_EXPORT": URL}
                opener = Opener(response)
                with patch.object(response, "read1", side_effect=reads), \
                     patch.object(triage.time, "monotonic", side_effect=ticks):
                    if reason is None:
                        result = triage.fetch(URL, destination, opener, progress=progress)
                        self.assertEqual(result["sha256"], triage.hashlib.sha256(b"abcd").hexdigest())
                    elif reason == "socket":
                        with self.assertRaises(TimeoutError):
                            triage.fetch(URL, destination, opener, progress=progress)
                    else:
                        with self.assertRaisesRegex(triage.Inconclusive, reason):
                            triage.fetch(URL, destination, opener, progress=progress)
                self.assertEqual(progress, {"stage": stage, "bytesRead": received, "bytesWritten": written,
                                            "elapsedMilliseconds": ticks[-1] * 1000, "complete": reason is None})
                self.assertEqual(destination.stat().st_size, written)
                self.assertEqual(len(opener.requests), 1)
                self.assertNotIn("NEVER_EXPORT", json.dumps(progress))

    def test_transfer_progress_open_header_and_overflow_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary).resolve() / "private.mp4"
            progress = {}
            for ticks, elapsed in (([0, 5], 5000), ([0, 3000000], 2147483647), ([5, 0], 0)):
                with patch.object(Opener, "open", side_effect=TimeoutError("NEVER_EXPORT")), \
                     patch.object(triage.time, "monotonic", side_effect=ticks), self.assertRaises(TimeoutError):
                    triage.fetch(URL, destination, Opener(None), progress=progress)
                self.assertEqual(progress, {"stage": "opening", "bytesRead": 0, "bytesWritten": 0,
                                            "elapsedMilliseconds": elapsed, "complete": False})
            self.assertFalse(destination.exists())
            for headers in ({"Set-Cookie": "NEVER_EXPORT"}, {"Content-Range": "NEVER_EXPORT"}):
                response = Response(headers=headers)
                with patch.object(triage.time, "monotonic", side_effect=[0, 1, 2]), \
                     patch.object(response, "read1") as read, self.assertRaises(triage.Inconclusive):
                    triage.fetch(URL, destination, Opener(response), progress=progress)
                read.assert_not_called()
                self.assertEqual(progress, {"stage": "validating_headers", "bytesRead": 0, "bytesWritten": 0,
                                            "elapsedMilliseconds": 2000, "complete": False})
                self.assertFalse(destination.exists())
                self.assertNotIn("NEVER_EXPORT", json.dumps(progress))
            with patch.object(triage, "CAP", 4), patch.object(triage.time, "monotonic", side_effect=[0, 1, 2, 3, 4]), \
                 self.assertRaisesRegex(triage.Inconclusive, "response_size_rejected"):
                triage.fetch(URL, destination, Opener(Response(b"abcde", status=200, headers={"Content-Type": "video/mp4"})),
                             progress=progress)
            self.assertEqual(progress, {"stage": "reading_body", "bytesRead": 5, "bytesWritten": 0,
                                        "elapsedMilliseconds": 4000, "complete": False})
            self.assertEqual(destination.stat().st_size, 0)

    def test_partial_transfer_progress_exports_without_hash_decode_or_private_data(self):
        for failure in ("deadline", "socket"):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                cache, _, _, _ = self.fixture(root)
                runner = root / "runner"
                runner.mkdir()
                response = Response(headers={"Content-Range": "bytes 0-15/16", "X-Private": "NEVER_EXPORT"})
                reads = [b"NEVER_EXPORT", TimeoutError("NEVER_EXPORT")]
                ticks = [0, 1, 2, 3, 36, 36] if failure == "deadline" else [0, 1, 2, 3, 4, 8]
                old = Path.cwd()
                try:
                    os.chdir(root)
                    with patch.dict(os.environ, {"SAME_ITEM_RENDER_DIAGNOSTICS": "true", "RUNNER_TEMP": str(runner),
                                                 "GITHUB_OUTPUT": str(root / "github-output")}), \
                         patch.object(triage, "container_cache", return_value=cache), \
                         patch.object(triage, "build_opener", return_value=Opener(response)), \
                         patch.object(response, "read1", side_effect=reads), \
                         patch.object(triage.time, "monotonic", side_effect=ticks), \
                         patch.object(triage, "decode") as decode, redirect_stdout(io.StringIO()) as console:
                        self.assertEqual(triage.main(), 0)
                    exports = [line for line in (root / "github-output").read_text().splitlines() if line.startswith("build/")]
                    self.assertEqual(len(exports), 1)
                    report_text = (root / exports[0]).read_text()
                    report = json.loads(report_text)
                    self.assertEqual(report["status"], "INCONCLUSIVE")
                    self.assertEqual(report["reason"], "network_deadline" if failure == "deadline" else "private_operation_failed")
                    self.assertEqual(report["transferProgress"], {"stage": "reading_body", "bytesRead": 12, "bytesWritten": 12,
                                                                 "elapsedMilliseconds": ticks[-1] * 1000, "complete": False})
                    self.assertNotIn("prefix", report)
                    self.assertNotIn("frames", report)
                    decode.assert_not_called()
                    self.assertTrue(report["cleanupVerified"])
                    self.assertFalse((cache / triage.LOCATOR).exists())
                    self.assertEqual(list(runner.iterdir()), [])
                    public = report_text + console.getvalue() + (root / "github-output").read_text()
                    for private in ("NEVER_EXPORT", URL, str(root), "X-Private"):
                        self.assertNotIn(private, public)
                finally:
                    os.chdir(old)

    def test_app_container_path_validation_and_symlink_cleanup_rejection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
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
                self.skipTest("Unprivileged symlink creation unavailable")
            with self.assertRaises(triage.Inconclusive):
                triage.cleanup_private(symlink, root)
            self.assertTrue(container.exists())

    def test_software_sequential_decode_actual_pts_export_and_metadata_allowlist(self):
        with tempfile.TemporaryDirectory() as temporary:
            private = Path(temporary).resolve()
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

    def test_runner_parent_alias_uses_canonical_root_for_creation_and_cleanup(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            cache, _, _, _ = self.fixture(root)
            parent = root / "real-parent"
            runner = parent / "runner"
            runner.mkdir(parents=True)
            alias = root / "parent-alias"
            try:
                alias.symlink_to(parent, target_is_directory=True)
            except OSError:
                self.skipTest("Unprivileged symlink creation unavailable")
            old = Path.cwd()
            try:
                os.chdir(root)
                with patch.dict(os.environ, {"SAME_ITEM_RENDER_DIAGNOSTICS": "true",
                                             "RUNNER_TEMP": str(alias / "runner"), "GITHUB_OUTPUT": ""}), \
                     patch.object(triage, "container_cache", return_value=cache), \
                     patch.object(triage, "fetch", side_effect=triage.Inconclusive("synthetic_stop")), \
                     patch.object(triage.tempfile, "mkdtemp", wraps=tempfile.mkdtemp) as create, \
                     patch.object(triage, "cleanup_private", wraps=triage.cleanup_private) as cleanup, \
                     redirect_stdout(io.StringIO()):
                    self.assertEqual(triage.main(), 0)
                report_path = next((root / "build/selected-media-triage").glob("run-*/report.json"))
                report = json.loads(report_path.read_text())
                self.assertEqual(report["reason"], "synthetic_stop")
                self.assertTrue(report["cleanupVerified"])
                private_creation = [call for call in create.call_args_list
                                    if call.kwargs.get("prefix") == "selected-media-private-"]
                self.assertEqual(len(private_creation), 1)
                self.assertEqual(private_creation[0].kwargs["dir"], runner)
                self.assertEqual(cleanup.call_args.args[1], runner)
                self.assertEqual(cleanup.call_args.args[0].parent, runner)
                self.assertEqual(list(runner.iterdir()), [])
            finally:
                os.chdir(old)

    def test_runner_leaf_alias_and_descendant_symlinks_remain_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            runner, foreign = root / "runner", root / "foreign"
            runner.mkdir()
            foreign.mkdir()
            protected = foreign / "selected-media-private-protected"
            protected.mkdir()
            sentinel = protected / "do-not-delete"
            sentinel.write_text("synthetic")
            leaf, descendant = root / "runner-alias", runner / "descendant"
            try:
                leaf.symlink_to(runner, target_is_directory=True)
                descendant.symlink_to(foreign, target_is_directory=True)
            except OSError:
                self.skipTest("Unprivileged symlink creation unavailable")
            with self.assertRaisesRegex(triage.Inconclusive, "unsafe_path"):
                triage.safe_path(descendant / protected.name / sentinel.name, runner)
            with self.assertRaisesRegex(triage.Inconclusive, "unsafe_path"):
                triage.cleanup_private(descendant / protected.name, runner)
            with patch.dict(os.environ, {"SAME_ITEM_RENDER_DIAGNOSTICS": "true", "RUNNER_TEMP": str(leaf)}), \
                 patch.object(triage, "container_cache") as cache, \
                 patch.object(triage, "fresh_export_directory", side_effect=triage.Inconclusive("synthetic_stop")), \
                 redirect_stdout(io.StringIO()) as console:
                self.assertEqual(triage.main(), 0)
            cache.assert_not_called()
            self.assertIn("private_root_rejected", console.getvalue())
            self.assertEqual(sentinel.read_text(), "synthetic")

    def test_required_real_tools_cannot_report_a_successful_skip(self):
        for required in ("true", "false"):
            with self.subTest(required=required), patch.dict(os.environ, {"REQUIRE_SELECTED_MEDIA_TOOLS": required}), \
                 patch.object(triage.shutil, "which", return_value=None):
                result = unittest.TestResult()
                TriageChecks("test_real_local_h264_aac_command_path").run(result)
                self.assertEqual(len(result.failures), 1 if required == "true" else 0)
                self.assertEqual(len(result.skipped), 0 if required == "true" else 1)
                self.assertEqual(result.errors, [])

    def test_real_local_h264_aac_command_path(self):
        if not (triage.shutil.which("ffprobe") and triage.shutil.which("ffmpeg")):
            if os.environ.get("REQUIRE_SELECTED_MEDIA_TOOLS") == "true":
                self.fail("Required ffprobe/FFmpeg pair unavailable; synthetic A/V tool compatibility unverified")
            self.skipTest("Local ffprobe/FFmpeg pair unavailable; synthetic A/V tool compatibility unverified")
        with tempfile.TemporaryDirectory() as temporary:
            private = Path(temporary).resolve()
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
                root = Path(temporary).resolve()
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
                def fake_fetch(url, prefix, progress=None):
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
            root = Path(temporary).resolve()
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
            private = Path(temporary).resolve()
            with self.assertRaisesRegex(triage.Inconclusive, "decode_incomplete_or_unsupported") as error:
                triage.private_process(["error"], private, "probe")
            self.assertNotIn("NEVER_EXPORT", str(error.exception))
            with patch.object(triage.time, "monotonic", side_effect=[0, 36]), self.assertRaisesRegex(triage.Inconclusive, "decode_deadline"):
                triage.private_process(["hang"], private, "decode")
            self.assertTrue(children[-1].killed)


class WorkflowChecks(unittest.TestCase):
    def test_explicit_diagnostic_tools_and_real_regression_precede_simulator(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/ios-tests.yml").read_text(encoding="utf-8")
        self.assertIn("      - name: Prepare explicit selected media diagnostic tools\n", workflow)
        self.assertIn("      - name: Verify synthetic selected media tools\n", workflow)
        prepare = workflow.split("      - name: Prepare explicit selected media diagnostic tools\n", 1)[1].split("      - name:", 1)[0]
        regression = workflow.split("      - name: Verify synthetic selected media tools\n", 1)[1].split("      - name:", 1)[0]
        for step in (prepare, regression):
            self.assertIn("if: ${{ inputs.same_item_render_diagnostics == true }}", step)
            self.assertRegex(step, r"timeout-minutes: [1-6]\n")
        pair_check = 'command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null'
        self.assertIn("if " + pair_check + "; then", prepare)
        self.assertLess(prepare.index(pair_check), prepare.index("brew install ffmpeg"))
        self.assertGreater(prepare.rindex(pair_check), prepare.index("brew install ffmpeg"))
        self.assertIn("HOMEBREW_NO_AUTO_UPDATE: '1'", prepare)
        self.assertNotIn("continue-on-error", prepare + regression)
        self.assertNotIn("|| true", prepare + regression)
        self.assertIn("REQUIRE_SELECTED_MEDIA_TOOLS: 'true'", regression)
        self.assertIn("python3 scripts/test-selected-media-triage.py TriageChecks.test_real_local_h264_aac_command_path", regression)
        self.assertLess(workflow.index("- name: Prepare explicit selected media diagnostic tools"),
                        workflow.index("- name: Verify synthetic selected media tools"))
        self.assertLess(workflow.index("- name: Verify synthetic selected media tools"),
                        workflow.index("- name: Generate native project"))

    def test_source_failure_message_only_runs_for_actual_source_failure(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/ios-tests.yml").read_text(encoding="utf-8")
        failure = workflow.split("      - name: Report real source gate failure\n", 1)[1].split("      - uses:", 1)[0]
        self.assertIn("if: ${{ !cancelled() && steps.source.outcome == 'failure' }}", failure)
        self.assertIn("exit 1", failure)


if __name__ == "__main__":
    unittest.main()
