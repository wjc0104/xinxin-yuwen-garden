"""Offline adversarial coverage; only the named synthetic-tool test runs FFmpeg."""
import contextlib
import copy
from fractions import Fraction
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import zlib

spec = importlib.util.spec_from_file_location("complete_object", Path(__file__).with_name("complete-object-control.py"))
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)
NONCE = "12345678-1234-1234-1234-123456789abc"
URL = "https://example.bilivideo.com/video.mp4?token=PRIVATE_URL_SENTINEL"
SENTINEL = "PRIVATE_URL_SENTINEL"


def box(kind, payload=b""):
    return struct.pack(">I4s", len(payload) + 8, kind) + payload


def full(kind, payload=b"", version=0, flags=0):
    return box(kind, bytes([version]) + flags.to_bytes(3, "big") + payload)


def table(kind, entries, width, version=0):
    return full(kind, struct.pack(">I", len(entries)) + b"".join(struct.pack(">" + width, *entry) for entry in entries), version)


def descriptor(tag, payload):
    assert len(payload) < 128
    return bytes([tag, len(payload)]) + payload


def fixture(offset_override=None, size_override=None, external=False, edit=0, add_unknown=False,
            bad_desc=False, duplicate=False, huge=False, video_count=1, fragment=False, co64=False):
    ftyp = box(b"ftyp", b"isom\0\0\0\0isomiso2avc1")
    payload = b"\0\0\0\x01v\0\0\0\x01a"
    mdat = box(b"mdat", payload)
    base = len(ftyp) + 8
    matrix = struct.pack(">9I", 65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824)
    def track(kind, number, offset):
        tkhd = full(b"tkhd", struct.pack(">5I", 0, 0, number, 0, 601000) + b"\0" * 16 + matrix +
                    struct.pack(">II", 1280 << 16 if kind == b"vide" else 0, 720 << 16 if kind == b"vide" else 0), flags=3)
        mdhd = full(b"mdhd", struct.pack(">4IHH", 0, 0, 1000, 601000, 0, 0))
        hdlr = full(b"hdlr", b"\0" * 4 + kind + b"\0" * 12 + b"\0")
        dref = full(b"dref", struct.pack(">I", 1) + full(b"url ", (URL.encode() + b"\0") if external else b"", flags=0 if external else 1))
        dinf = box(b"dinf", dref)
        sample_header = b"\0" * 6 + struct.pack(">H", 2 if bad_desc else 1)
        if kind == b"vide":
            header = sample_header + b"\0" * 16 + struct.pack(">HH", 1280, 720) + b"\0" * 50
            avcc = box(b"avcC", b"\x01\x42\0\x1e\xff\xe1\0\x02\x67\x42\x01\0\x01\x68")
            stsd = full(b"stsd", struct.pack(">I", 1) + box(b"avc1", header + avcc))
            media_header = full(b"vmhd", b"\0" * 8, flags=1)
        else:
            header = sample_header + b"\0" * 8 + struct.pack(">HHHHI", 2, 16, 0, 0, 48000 << 16)
            config = descriptor(4, bytes([0x40, 0x15]) + b"\0" * 11 + descriptor(5, b"\x11\x90"))
            esds = full(b"esds", descriptor(3, b"\0\x01\0" + config + descriptor(6, b"\x02")))
            stsd = full(b"stsd", struct.pack(">I", 1) + box(b"mp4a", header + esds))
            media_header = full(b"smhd", b"\0" * 4)
        stts = table(b"stts", [(1, 601000)], "II")
        stsc = table(b"stsc", [(1, 1, 2 if bad_desc else 1)], "III")
        stsz = full(b"stsz", struct.pack(">II", size_override or 5, 1))
        stco = table(b"co64" if co64 else b"stco", [(offset_override if offset_override is not None else offset,)], "Q" if co64 else "I")
        if huge:
            stco = full(b"stco", struct.pack(">I", 0xffffffff))
        stbl = box(b"stbl", stsd + stts + stsc + stsz + stco + (stco if duplicate else b""))
        minf = box(b"minf", media_header + dinf + stbl)
        edits = b""
        if edit is not None:
            edits = box(b"edts", full(b"elst", struct.pack(">IIihh", 1, 601000, edit, 1, 0)))
        return box(b"trak", tkhd + edits + box(b"mdia", mdhd + hdlr + minf) + (box(b"uuid", b"x" * 16) if add_unknown else b""))
    mvhd = full(b"mvhd", struct.pack(">4I", 0, 0, 1000, 601000) + b"\0" * 80)
    tracks = b"".join(track(b"vide", index + 1, base) for index in range(video_count)) + track(b"soun", 9, base + 5)
    return ftyp + mdat + box(b"moov", mvhd + tracks) + (box(b"moof", b"") if fragment else b"")


def png(extra=None, crc_bad=False):
    def chunk(kind, data):
        crc = zlib.crc32(kind + data) & 0xffffffff
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc ^ int(crc_bad))
    raw = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1280, 720, 8, 2, 0, 0, 0))
    if extra:
        raw += chunk(*extra)
    return raw + chunk(b"IDAT", zlib.compress((b"\0" + b"\x10\x20\x30" * 1280) * 720)) + chunk(b"IEND", b"")


def result_for(expected, targets=(5, 15, 25, 52), complete=True):
    frames = []
    for target in targets:
        paused = target == 52
        frames.append({"targetSeconds": target, "paused": paused, "state": "decoded-output-gates-passed",
                       "exportState": "attached", "actualPTSValue": target * 1000, "actualPTSTimescale": 1000,
                       "actualPTSFlags": 1, "actualPTSEpoch": 0, "actualPTSSeconds": target,
                       "currentBeforeSeconds": target, "currentAfterSeconds": target, "requestedSeconds": target,
                       "rateBefore": 0 if paused else 1.5, "rateAfter": 0 if paused else 1.5,
                       "controlBefore": 0 if paused else 2, "controlAfter": 0 if paused else 2,
                       "imageAttachmentsPreserved": True, "width": 1280, "height": 720,
                       "samples": 1000, "populatedColors": 17, "largestBucket": 400})
    claim = {k: expected[k] for k in ("bytes", "sha256")}
    return {"schema": 1, "scope": "localCompleteObjectDecodedOutput", "nonce": expected["nonce"],
            "fileBefore": claim, "fileAfter": claim, "sourceHashVerified": True,
            "completed": complete, "captureCompleted": complete, "artifactsSucceeded": True,
            "exactPlainClasses": True, "sharedAssetObject": True, "controllerInWindow": True, "frames": frames}


class Response:
    def __init__(self, body=b"abcdef", headers=None, status=200, url=URL):
        self.body, self.status, self.url = io.BytesIO(body), status, url
        self.headers = {"Content-Length": str(len(body)), "Content-Type": "video/mp4", **(headers or {})}
    def read1(self, n): return self.body.read(n)
    def geturl(self): return self.url
    def __enter__(self): return self
    def __exit__(self, *_): return False


class Opener:
    def __init__(self, response): self.response, self.calls = response, 0
    def open(self, request, timeout):
        self.calls += 1; self.request, self.timeout = request, timeout
        return self.response


class CompleteObjectChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.expected = {"schema": 1, "nonce": NONCE, "bytes": 1234, "sha256": "a" * 64}
    def tearDown(self):
        # Windows's read-only fixtures must be made writable before TemporaryDirectory.
        for root, _, files in os.walk(self.root):
            for name in files:
                path = Path(root) / name
                if not path.is_symlink(): path.chmod(0o600)
        self.temp.cleanup()
    def rejects(self, call, reason=None):
        with self.assertRaises(c.Inconclusive) as caught: call()
        if reason: self.assertEqual(str(caught.exception), reason)
        self.assertIn(str(caught.exception), c.REASONS)
    def test_complete_synthetic_grammar(self):
        self.assertEqual(c.MP4(fixture()).validate()["videoTracks"], 1)
        self.assertTrue(c.MP4(fixture(co64=True)).validate()["selfContained"])
        self.assertTrue(c.MP4(fixture(edit=None)).validate()["identityTimeline"])
    def test_external_dref_never_reaches_consumers(self):
        self.rejects(lambda: c.MP4(fixture(external=True)).validate(), "mp4_external_reference")
    def test_chunk_span_crosses_mdat_or_points_into_moov(self):
        for raw in (fixture(size_override=6), fixture(offset_override=1), fixture(offset_override=999999)):
            with self.subTest(): self.rejects(lambda: c.MP4(raw).validate(), "mp4_sample_span")
    def test_duplicate_missing_table_bad_description(self):
        for raw in (fixture(duplicate=True), fixture(bad_desc=True), fixture().replace(b"stsz", b"junk", 1)):
            with self.subTest(): self.rejects(lambda: c.MP4(raw).validate())
    def test_fragment_external_unknown_and_nonidentity_edit(self):
        for args in ({"fragment": True}, {"add_unknown": True}, {"edit": 1}, {"video_count": 2}):
            with self.subTest(args=args): self.rejects(lambda: c.MP4(fixture(**args)).validate())
    def test_truncation_huge_counts_zero_size_and_unknown_metadata(self):
        for raw in (fixture()[:-1], fixture(huge=True), b"\0\0\0\0mdat", fixture() + box(b"meta"), fixture() + box(b"rmra")):
            with self.subTest(): self.rejects(lambda: c.MP4(raw).validate())
    def test_box_and_entry_budgets(self):
        self.rejects(lambda: c.MP4(box(b"free") * 10001).validate(), "mp4_budget")
        parser = c.MP4(fixture())
        self.rejects(lambda: parser.spend(500001), "mp4_budget")
        self.rejects(lambda: parser.children(0, 8, 9), "mp4_budget")
    def test_audio_url_flag_and_reference_movie(self):
        raw = fixture()
        # ES descriptor dependency/URL flags are rejected, even without a matching URL payload.
        marker = b"\x03\x19\0\x01\0"
        self.assertIn(marker, raw)
        self.rejects(lambda: c.MP4(raw.replace(marker, marker[:-1] + b"\x40", 1)).validate(), "mp4_external_reference")
    def test_fetch_exact_known_200_and_full_206(self):
        for status, headers in ((200, {}), (206, {"Content-Range": "bytes 0-5/6"})):
            opener = Opener(Response(status=status, headers=headers))
            path = self.root / str(status)
            self.assertEqual(c.fetch(URL, path, opener)["bytes"], 6)
            self.assertEqual(path.read_bytes(), b"abcdef")
            self.assertEqual(opener.calls, 1)
            self.assertEqual(opener.timeout, 5)
            self.assertEqual(opener.request.get_header("Range"), f"bytes=0-{c.CAP - 1}")
    def test_fetch_rejects_partial_unknown_oversized_credentials_mime_encoding(self):
        cases = [(206, {"Content-Range": "bytes 0-5/7"}), (200, {"Content-Length": ""}),
                 (200, {"Content-Length": str(c.CAP + 1)}), (200, {"Set-Cookie": SENTINEL}),
                 (200, {"WWW-Authenticate": SENTINEL}), (200, {"Content-Encoding": "gzip"}),
                 (200, {"Content-Type": "text/html"}), (200, {"Content-Length": "5"}),
                 (200, {"Content-Length": "7"}), (200, {"Content-Range": "bytes 0-5/6"})]
        for index, (status, headers) in enumerate(cases):
            opener = Opener(Response(status=status, headers=headers))
            with self.subTest(headers=headers): self.rejects(lambda: c.fetch(URL, self.root / str(index), opener))
            self.assertEqual(opener.calls, 1)
    def test_fetch_absolute_deadline(self):
        opener = Opener(Response())
        clock = iter([0, 1, 2, 36])
        self.rejects(lambda: c.fetch(URL, self.root / "timeout", opener, lambda: next(clock)), "network_deadline")
        self.assertEqual(opener.calls, 1)
    def test_fetch_cap_plus_one_read_never_writes_excess(self):
        response = Response(body=b"x" * 9, headers={"Content-Length": "8"})
        read = []
        original = response.read1
        def read1(n):
            chunk = original(n); read.append(len(chunk)); return chunk
        response.read1 = read1
        path = self.root / "oversize"
        with patch.object(c, "CAP", 8):
            self.rejects(lambda: c.fetch(URL, path, Opener(response)), "response_size_rejected")
        self.assertLessEqual(sum(read), 9)
        self.assertLessEqual(path.stat().st_size, 8)
    def test_duplicate_http_framing_rejected(self):
        from email.message import Message
        response = Response()
        headers = Message()
        headers["Content-Length"] = "6"; headers["Content-Length"] = "6"
        headers["Content-Type"] = "video/mp4"
        response.headers = headers
        self.rejects(lambda: c.fetch(URL, self.root / "duplicate", Opener(response)), "range_rejected")
    def test_url_redirect_trust(self):
        for url in ("http://x.bilivideo.com/a", "https://bilivideo.com.evil.test/a", "https://u:p@x.bilivideo.com/a",
                    "https://x.bilivideo.com:444/a", "https://x.bilivideo.com/a#x", "file:///tmp/a", "https://127.0.0.1/a"):
            self.assertFalse(c.approved_url(url))
        self.assertTrue(c.approved_url(URL))
        redirects = c.Redirects(time.monotonic() + 35)
        request = c.Request(URL)
        self.rejects(lambda: redirects.redirect_request(request, None, 302, "", {}, "https://evil.test/a"), "redirect_rejected")
        self.rejects(lambda: redirects.redirect_request(request, None, 302, "", {"Set-Cookie": SENTINEL}, URL), "credentials_rejected")
        redirects.hops = 3
        self.rejects(lambda: redirects.redirect_request(request, None, 302, "", {}, URL), "redirect_limit")
    def test_locator_read_only_and_schema(self):
        row = {"schema": 1, "generation": 1, "launch": NONCE, "identityNamespace": "same-item-render-launch-local", "url": URL}
        self.assertEqual(c.locator_url(row), URL)
        for key, value in (("generation", True), ("launch", "x" * 36), ("identityNamespace", "wrong"), ("url", "https://evil.test")):
            bad = {**row, key: value}
            self.rejects(lambda: c.locator_url(bad), "locator_rejected")
    def test_manifest_duplicates_nonfinite_and_path_redaction(self):
        self.assertEqual(c.manifest(self.expected), self.expected)
        for row in ({**self.expected, "path": SENTINEL}, {**self.expected, "bytes": True}, {**self.expected, "nonce": "../"}):
            self.rejects(lambda: c.manifest(row), "manifest_rejected")
        self.rejects(lambda: c.unique_json(b'{"schema":1,"schema":2}'), "metadata_schema")
        self.rejects(lambda: c.unique_json(b'{"x":NaN}'), "metadata_schema")
    def test_path_traversal_symlink_and_hardlink(self):
        self.rejects(lambda: c.safe_path(self.root / "../escape", self.root), "unsafe_path")
        target = self.root / "target"; target.write_bytes(b"data"); target.chmod(0o400)
        try:
            (self.root / "alias").symlink_to(target)
        except OSError:
            pass
        else:
            self.rejects(lambda: c.safe_path(self.root / "alias", self.root), "unsafe_path")
        os.link(target, self.root / "hardlink")
        self.rejects(lambda: c.identity(target, self.root), "source_unavailable")
    def test_same_inode_hash_size_and_replacement_mutations(self):
        path = self.root / "source.mp4"; path.write_bytes(fixture()); path.chmod(0o400)
        before = c.identity(path, self.root)
        self.assertEqual(c.identity(path, self.root, before), before)
        path.chmod(0o600); data = path.read_bytes(); path.write_bytes(data[:-1] + bytes([data[-1] ^ 1])); path.chmod(0o400)
        self.rejects(lambda: c.identity(path, self.root, before), "source_changed")
        path.chmod(0o600); path.unlink(); path.write_bytes(data); path.chmod(0o400)
        self.rejects(lambda: c.identity(path, self.root, before), "source_changed")
    def test_result_finite_allowlist_drops_untrusted_strings(self):
        row = result_for(self.expected)
        row.update(path=SENTINEL, arbitrary=SENTINEL, stage=SENTINEL)
        row["frames"][0].update(filename=SENTINEL, message=SENTINEL, pts_time=SENTINEL)
        clean = c.sanitize_result(row, self.expected)
        self.assertNotIn(SENTINEL, json.dumps(clean))
        self.assertTrue(c.capture_gates(clean))
        row["frames"][0]["rateBefore"] = float("nan")
        self.rejects(lambda: c.sanitize_result(row, self.expected), "result_rejected")
    def test_actual_pts_flags_epoch_fraction_and_535_limit(self):
        for key, value in (("actualPTSFlags", 5), ("actualPTSFlags", 32), ("actualPTSEpoch", 1),
                           ("actualPTSTimescale", 0), ("actualPTSValue", 54000)):
            row = result_for(self.expected)
            row["frames"][-1][key] = value
            self.rejects(lambda: c.sanitize_result(row, self.expected), "returned_pts_invalid")
        row = result_for(self.expected)
        row["frames"][-1]["actualPTSValue"] = 53500
        clean = c.sanitize_result(row, self.expected)
        self.assertEqual(Fraction(clean["frames"][-1]["actualPTSValue"], clean["frames"][-1]["actualPTSTimescale"]), Fraction(107, 2))
        self.assertFalse(c.capture_gates(clean))  # Not aligned with before/after=52.
    def test_partial_first_buffer_cannot_be_pass(self):
        row = result_for(self.expected, (5,), complete=False)
        row["frames"][0]["state"] = "first-buffer"
        row["frames"][0]["populatedColors"] = 1
        clean = c.sanitize_result(row, self.expected)
        self.assertEqual(len(clean["frames"]), 1)
        self.assertFalse(c.capture_gates(clean))
        row["completed"] = True
        self.assertFalse(c.capture_gates(c.sanitize_result(row, self.expected)))
    def test_png_crc_structure_and_metadata_allowlist(self):
        valid = png(); self.assertEqual(c.validate_png(valid), valid)
        for kind in (b"tEXt", b"zTXt", b"iTXt", b"eXIf", b"iCCP", b"abcd"):
            self.rejects(lambda: c.validate_png(png((kind, SENTINEL.encode()))), "png_metadata_rejected")
        for raw in (png(crc_bad=True), valid[:-1], valid + b"x", valid[:8] + valid[33:]):
            self.rejects(lambda: c.validate_png(raw), "png_rejected")
    def test_png_deflate_bomb_wrong_dimensions_and_extra_stream(self):
        raw = png()
        self.rejects(lambda: c.validate_png(raw.replace(struct.pack(">I", 1280), struct.pack(">I", 1281), 1)), "png_rejected")
        def chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)
        bomb = raw[:33] + chunk(b"IDAT", zlib.compress(b"\0" * (720 * 3841 + 1))) + chunk(b"IEND", b"")
        self.rejects(lambda: c.validate_png(bomb), "png_rejected")
    def test_png_apple_metadata_removed_without_reencoding(self):
        def chunk(kind, payload):
            return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xffffffff)
        original = png()
        raw = original[:33] + chunk(b"eXIf", ("Orientation=6;https://token/" + SENTINEL).encode()) + \
              chunk(b"iDOT", SENTINEL.encode()) + original[33:]
        raw_hash = hashlib.sha256(raw).hexdigest()
        cleaned, proof = c.sanitize_png(raw)
        self.assertEqual(cleaned, original)  # all encoded image/color chunks byte-identical
        self.assertNotIn(SENTINEL.encode(), cleaned)
        self.assertEqual(proof["encodedSHA256"], raw_hash)
        self.assertEqual(proof["publishedSHA256"], hashlib.sha256(cleaned).hexdigest())
        self.assertTrue(proof["IDATBytesUnchanged"])
        self.assertFalse(proof["metadataDisplayInterpretationApplied"])
        self.assertEqual(hashlib.sha256(raw).hexdigest(), raw_hash)
        # Stripping is not a general metadata/repair path: CRC, trailing data,
        # text and every other unrecognized ancillary kind still reject.
        bad = bytearray(raw); bad[48] ^= 1
        self.rejects(lambda: c.sanitize_png(bytes(bad)), "png_rejected")
        self.rejects(lambda: c.sanitize_png(raw + b"trailing"), "png_rejected")
        self.rejects(lambda: c.sanitize_png(png((b"tEXt", SENTINEL.encode()))), "png_metadata_rejected")
        self.rejects(lambda: c.sanitize_png(png((b"abcd", SENTINEL.encode()))), "png_metadata_rejected")
    def test_process_timeout_log_limit_and_private_output(self):
        for index, (code, budget, cap, reason) in enumerate((("import time;time.sleep(10)", 0.05, 1024, "process_deadline"),
              ("import sys;sys.stdout.write('x'*100000)", 5, 1024, "process_output_limit"))):
            private = self.root / str(index); private.mkdir()
            self.rejects(lambda: c.private_process([sys.executable, "-B", "-c", code], private, "test", budget, cap), reason)
            self.assertFalse((private / "host-active").exists())
            self.assertLessEqual((private / "test.stdout").stat().st_size, cap)
    def test_process_cancellation_stops_owned_child_and_waits(self):
        private = self.root / "cancel"; private.mkdir()
        real_clock = time.monotonic
        calls = [0]
        def cancel_once():
            calls[0] += 1
            if calls[0] == 1: raise c.Inconclusive("cancelled")
            return real_clock()
        with patch.object(c.time, "monotonic", side_effect=cancel_once):
            self.rejects(lambda: c.private_process([sys.executable, "-B", "-c", "pass"], private, "cancel"), "cancelled")
        self.assertFalse((private / "host-active").exists())
    @unittest.skipUnless(os.name == "posix", "POSIX process-group/descendant assertion runs on macOS CI")
    def test_descendant_group_is_stopped_and_waited(self):
        private = self.root / "child"; private.mkdir()
        # Both descendants and parent receive the group signal; the parent reaps
        # its child so a zombie cannot be mistaken for a surviving writer.
        code = ("import os,time,signal,sys\np=os.fork()\n"
                "if p == 0: time.sleep(10)\n"
                "else:\n signal.signal(signal.SIGTERM,lambda *_:(os.waitpid(p,0),sys.exit(0)))\n time.sleep(10)\n")
        self.rejects(lambda: c.private_process([sys.executable, "-B", "-c", code], private, "child", 0.1),
                     "process_deadline")
        self.assertFalse((private / "host-active").exists())
    def test_shutdown_exact_udid_state_required(self):
        for state, udid in (("Booted", NONCE), ("Shutting Down", NONCE), ("Shutdown", "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")):
            raw = json.dumps({"devices": {"runtime": [{"udid": udid, "state": state}]}}).encode()
            with patch.object(c, "bounded_tool", side_effect=[(1, b""), (0, raw)]):
                self.rejects(lambda: c.quiesce(NONCE), "cleanup_unverified")
        raw = json.dumps({"devices": {"runtime": [{"udid": NONCE, "state": "Shutdown"}]}}).encode()
        with patch.object(c, "bounded_tool", side_effect=[(1, b"already shutdown"), (0, raw)]): c.quiesce(NONCE)
    def test_cleanup_namespace_only_preserves_old_locator(self):
        cache = self.root / "cache"; cache.mkdir()
        runner = self.root / "runner"; runner.mkdir()
        directory = cache / c.NAMESPACE; directory.mkdir()
        (directory / "source.mp4").write_bytes(b"raw")
        locator = cache / c.LOCATOR; locator.write_text(SENTINEL)
        private = runner / (c.PRIVATE_PREFIX + NONCE); private.mkdir()
        (private / "CompleteObject.xcresult").mkdir()
        c.cleanup(cache, runner, private)
        self.assertEqual(locator.read_text(), SENTINEL)
        self.assertFalse(directory.exists()); self.assertFalse(private.exists())
    def test_cleanup_fallback_refuses_unowned_or_active_run(self):
        cache = self.root / "cache"; cache.mkdir()
        runner = self.root / "runner"; runner.mkdir()
        directory = cache / c.NAMESPACE; directory.mkdir()
        (directory / "source.mp4").write_bytes(b"raw")
        self.rejects(lambda: c.cleanup(cache, runner, fallback=True), "cleanup_unverified")
        self.assertTrue((directory / "source.mp4").exists())
        private = runner / (c.PRIVATE_PREFIX + NONCE); private.mkdir()
        (private / "host-active").write_text("1")
        self.rejects(lambda: c.cleanup(cache, runner, private), "cleanup_unverified")
        self.rejects(lambda: c.cleanup(cache, runner, owned=False), "cleanup_unverified")
        (private / "host-active").unlink()
        c.cleanup(cache, runner, private)
        c.cleanup(cache, runner, fallback=True)
    def test_cleanup_unverified_has_no_github_paths(self):
        cache = self.root / "cache"; cache.mkdir()
        runner = self.root / "runner"; runner.mkdir()
        output = self.root / "github-output"
        env = {"COMPLETE_OBJECT_SAME_BYTES": "true", "SAME_ITEM_RENDER_DIAGNOSTICS": "true", "SIMULATOR_ID": NONCE,
               "RUNNER_TEMP": str(runner), "GITHUB_OUTPUT": str(output)}
        with patch.dict(os.environ, env), patch.object(c, "container_cache", return_value=cache), \
             patch.object(c, "quiesce", side_effect=c.Inconclusive("cleanup_unverified")), contextlib.redirect_stdout(io.StringIO()) as console:
            self.assertEqual(c.main([]), 1)
        self.assertFalse(output.exists()); self.assertNotIn(SENTINEL, console.getvalue())
    def test_invalid_opt_in_and_missing_runner_cannot_start_native_tools(self):
        with patch.dict(os.environ, {"COMPLETE_OBJECT_SAME_BYTES": "true", "SAME_ITEM_RENDER_DIAGNOSTICS": "false"}), \
             patch.object(c, "quiesce") as shutdown, patch.object(c, "container_cache") as container, \
             contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(c.main([]), 1)
        shutdown.assert_not_called(); container.assert_not_called()
        for value in ("", "relative", None):
            self.rejects(lambda: c.runner_root(value), "private_root_rejected")
    def exercise_coordinator(self, partial=False, mutate=False, cleanup_fail=False, bad_mp4=False):
        cache = self.root / "cache"; cache.mkdir()
        runner = self.root / "runner"; runner.mkdir()
        locator = cache / c.LOCATOR
        locator.write_text(json.dumps({"schema": 1, "generation": 1, "launch": NONCE, "identityNamespace": "same-item-render-launch-local", "url": URL}))
        published = []
        calls = []
        def fetch(url, source):
            raw = fixture(external=bad_mp4); source.write_bytes(raw)
            return {"bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()}
        def capture(command, private, stem, **kwargs):
            calls.append(command)
            directory = cache / c.NAMESPACE
            expected = json.loads((directory / "manifest.json").read_text())
            result = result_for(expected, (5,) if partial else (5, 15, 25, 52), not partial)
            result["unknownPrivatePath"] = SENTINEL
            for target in ((5,) if partial else (5, 15, 25, 52)):
                (directory / c.TARGETS[target]).write_bytes(png())
            (directory / "result.json").write_text(json.dumps(result))
            if mutate:
                source = directory / "source.mp4"; source.chmod(0o600); source.write_bytes(b"changed"); source.chmod(0o400)
            return private / "unused", 1 if partial else 0
        def decode(source, private, requested):
            return {"frames": [{"targetSeconds": row["targetSeconds"], "exactRationalPTSMatch": True} for row in requested]}, \
                   {f"software-{row['targetSeconds']:02d}.png": png() for row in requested}
        env = {"COMPLETE_OBJECT_SAME_BYTES": "true", "SAME_ITEM_RENDER_DIAGNOSTICS": "true", "SIMULATOR_ID": NONCE, "RUNNER_TEMP": str(runner)}
        quiesce = c.Inconclusive("cleanup_unverified") if cleanup_fail else None
        with patch.dict(os.environ, env), patch.object(c, "container_cache", return_value=cache), \
             patch.object(c, "fetch", side_effect=fetch), patch.object(c, "private_process", side_effect=capture), \
             patch.object(c, "quiesce", side_effect=quiesce), patch.object(c, "decode", side_effect=decode), \
             patch.object(c, "publish", side_effect=lambda report, images: published.append((copy.deepcopy(report), dict(images)))), \
             contextlib.redirect_stdout(io.StringIO()) as console:
            code = c.main([])
        self.assertEqual(code, 1 if partial or mutate or cleanup_fail or bad_mp4 else 0)
        self.assertTrue(locator.exists())
        self.assertNotIn(SENTINEL, console.getvalue())
        self.assertNotIn(SENTINEL, json.dumps([r for r, _ in published]))
        return published, calls, cache, runner
    def test_coordinator_success_same_source_cleanup_before_publish(self):
        published, calls, cache, runner = self.exercise_coordinator()
        report, images = published[0]
        self.assertEqual(report["status"], "COMPLETE")
        self.assertFalse(report["priorBytesEqualityEstablished"])
        self.assertTrue(report["sameNewObjectBytesEstablished"])
        self.assertTrue(report["cleanupVerified"])
        self.assertEqual(len(images), 8); self.assertEqual(len(calls), 1)
        self.assertFalse((cache / c.NAMESPACE).exists()); self.assertEqual(list(runner.iterdir()), [])
    def test_coordinator_partial_keeps_first_png_but_never_pass(self):
        published, calls, _, _ = self.exercise_coordinator(partial=True)
        report, images = published[0]
        self.assertEqual(report["status"], "CONTROL_FAILED"); self.assertTrue(report["partial"])
        self.assertEqual(set(images), {"avf-05.png", "software-05.png"}); self.assertEqual(len(calls), 1)
    def test_coordinator_mutation_or_cleanup_failure_never_publishes_images(self):
        published, _, _, _ = self.exercise_coordinator(mutate=True)
        self.assertEqual(published[0][0]["reason"], "source_changed"); self.assertEqual(published[0][1], {})
    def test_coordinator_shutdown_failure_never_publishes_any_paths(self):
        published, _, _, _ = self.exercise_coordinator(cleanup_fail=True)
        self.assertEqual(published, [])
    def test_unsupported_container_launches_no_consumer(self):
        published, calls, _, _ = self.exercise_coordinator(bad_mp4=True)
        self.assertEqual(calls, [])
        self.assertEqual(published[0][0]["status"], "INCONCLUSIVE")
    def test_decode_exact_fraction_not_nearest_and_file_only_commands(self):
        private = self.root / "decode"; private.mkdir()
        source = self.root / "source.mp4"; source.write_bytes(b"unused")
        commands = []
        def process(command, private, stem, **kwargs):
            commands.append(command)
            path = private / (stem + ".stdout")
            if stem == "probe":
                path.write_text(json.dumps({"streams": [{"codec_name": "h264", "width": 1280, "height": 720,
                    "start_pts": 0, "time_base": "1/30"}], "frames": [{"pts": 1, "width": 1280, "height": 720}]}))
            else:
                path.write_bytes(b""); (private / "software-1.png").write_bytes(png())
            return path, 0
        requested = [{"targetSeconds": 5, "actualPTSValue": 2, "actualPTSTimescale": 60}]
        with patch.object(c.shutil, "which", side_effect=lambda name: name), patch.object(c, "private_process", side_effect=process):
            decoded, images = c.decode(source, private, requested)
            self.assertEqual(decoded["frames"][0]["softwarePTS"], 1)
            requested[0]["actualPTSValue"] = 3
            self.rejects(lambda: c.decode(source, private, requested), "exact_pts_unavailable")
        for command in commands:
            self.assertEqual(command[command.index("-protocol_whitelist") + 1], "file")
            self.assertEqual(command[command.index("-format_whitelist") + 1], "mov")
            self.assertNotIn("-ss", command); self.assertNotIn("-itsoffset", command)
        decoder = commands[1]
        self.assertEqual(decoder[decoder.index("-map_metadata") + 1], "-1")
        self.assertEqual(decoder[decoder.index("-map_chapters") + 1], "-1")
        self.assertEqual(commands[0][commands[0].index("-read_intervals") + 1], "%+54")
    def test_publish_allowlist_and_no_paths_before_cleanup(self):
        output = self.root / "output"
        previous = Path.cwd()
        try:
            os.chdir(self.root)
            with patch.dict(os.environ, {"GITHUB_OUTPUT": str(output)}):
                self.rejects(lambda: c.publish({"cleanupVerified": False}, {}), "cleanup_unverified")
                self.assertFalse(output.exists())
                c.publish({"schema": 1, "cleanupVerified": True, "reason": "same_bytes_complete"}, {"avf-05.png": png()})
                names = output.read_text()
                self.assertIn("build/complete-object-control/run-", names)
                self.assertNotIn(str(self.root), names)
                self.assertNotIn(SENTINEL, names)
        finally:
            os.chdir(previous)
    def test_cleanup_only_residue_fails_closed_nonzero(self):
        cache = self.root / "cache"; cache.mkdir()
        (cache / c.NAMESPACE).mkdir()
        runner = self.root / "runner"; runner.mkdir()
        output = self.root / "output"
        env = {"COMPLETE_OBJECT_SAME_BYTES": "true", "SAME_ITEM_RENDER_DIAGNOSTICS": "true", "SIMULATOR_ID": NONCE,
               "RUNNER_TEMP": str(runner), "GITHUB_OUTPUT": str(output)}
        with patch.dict(os.environ, env), patch.object(c, "container_cache", return_value=cache), \
             patch.object(c, "quiesce"), contextlib.redirect_stdout(io.StringIO()) as console:
            self.assertEqual(c.main(["--cleanup-only"]), 1)
        self.assertTrue((cache / c.NAMESPACE).exists()); self.assertFalse(output.exists())
        self.assertIn("cleanup_unverified", console.getvalue())
    def _decode_synthetic_fixture_with_pts_evidence(self, source, private, requested):
        try:
            return c.decode(source, private, requested)
        except c.Inconclusive as error:
            if str(error) == "exact_pts_unavailable":
                # This method owns a locally generated synthetic fixture only.
                # Reuse decode's existing bounded probe result: no second probe,
                # raw dict/metadata/path/error text, nearest-match substitution,
                # timestamp rewrite, relaxed gate, or swallowed failure.
                try:
                    data = c.bounded_json(private / "probe.stdout", private, 4 * 1024 * 1024)
                    streams, frames = data.get("streams"), data.get("frames")
                    if not (isinstance(streams, list) and len(streams) == 1 and
                            isinstance(frames, list) and 0 < len(frames) <= 10000):
                        raise ValueError()
                    text_base = streams[0].get("time_base")
                    if not (isinstance(text_base, str) and len(text_base) <= 32):
                        raise ValueError()
                    base = Fraction(text_base)
                    if not (0 < base.numerator <= 10 ** 10 and 0 < base.denominator <= 10 ** 10):
                        raise ValueError()
                    start_pts = streams[0].get("start_pts")
                    if type(start_pts) is not int or not -(1 << 63) <= start_pts < (1 << 63):
                        raise ValueError()
                    ticks = []
                    for frame in frames:
                        value = frame.get("pts") if isinstance(frame, dict) else None
                        if type(value) is not int or not -(1 << 63) <= value < (1 << 63):
                            raise ValueError()
                        ticks.append(value)
                    def witness(tick):
                        value = tick * base
                        return {"pts": tick, "secondsNumerator": value.numerator,
                                "secondsDenominator": value.denominator}
                    pairs = []
                    for target in (5, 15, 25, 52):
                        lower = [tick for tick in ticks if tick * base <= target]
                        upper = [tick for tick in ticks if tick * base >= target]
                        pairs.append({"targetSeconds": target, "exactPresent": any(tick * base == target for tick in ticks),
                                      "lower": witness(max(lower)) if lower else None,
                                      "upper": witness(min(upper)) if upper else None})
                    diagnostic = {"schema": 1, "scope": "syntheticFixturePTSOnly", "frameCount": len(ticks),
                                  "streamStartPTS": start_pts, "timeBaseNumerator": base.numerator, "timeBaseDenominator": base.denominator,
                                  "first": [witness(tick) for tick in ticks[:4]],
                                  "last": [witness(tick) for tick in ticks[-4:]], "targets": pairs}
                    encoded = json.dumps(diagnostic, sort_keys=True, separators=(",", ":"), allow_nan=False)
                    if len(encoded) > 4000:
                        raise ValueError()
                    print("COMPLETE_OBJECT_SYNTHETIC_PTS " + encoded, flush=True)
                except Exception:
                    print("COMPLETE_OBJECT_SYNTHETIC_PTS unavailable", flush=True)
            raise
    def test_synthetic_failure_pts_evidence_is_bounded_numeric_and_rethrows(self):
        private = self.root / "synthetic"; private.mkdir()
        pts = [0, 151, 451, 751, 1561, 1591]
        data = {"streams": [{"time_base": "1/30", "start_pts": 0, "tags": {"path": SENTINEL}}],
                "frames": [{"pts": tick, "arbitrary": SENTINEL} for tick in pts], "path": SENTINEL}
        (private / "probe.stdout").write_text(json.dumps(data))
        failure = c.Inconclusive("exact_pts_unavailable")
        with patch.object(c, "decode", side_effect=failure), contextlib.redirect_stdout(io.StringIO()) as console:
            with self.assertRaises(c.Inconclusive) as caught:
                self._decode_synthetic_fixture_with_pts_evidence(self.root / "source.mp4", private, [])
        self.assertIs(caught.exception, failure)
        output = console.getvalue()
        self.assertLessEqual(len(output.encode("utf-8")), 4096)
        self.assertNotIn(SENTINEL, output); self.assertNotIn(str(self.root), output)
        evidence = json.loads(output.removeprefix("COMPLETE_OBJECT_SYNTHETIC_PTS "))
        self.assertEqual(set(evidence), {"schema", "scope", "frameCount", "streamStartPTS", "timeBaseNumerator",
                                        "timeBaseDenominator", "first", "last", "targets"})
        self.assertEqual(evidence["frameCount"], len(pts))
        self.assertEqual(evidence["targets"][0]["lower"]["pts"], 0)
        self.assertEqual(evidence["targets"][0]["upper"]["pts"], 151)
        self.assertFalse(evidence["targets"][0]["exactPresent"])
        self.assertEqual(evidence["targets"][-1]["upper"]["secondsNumerator"], 1561)
    def test_synthetic_failure_pts_wrong_fields_do_not_escape_or_swallow(self):
        private = self.root / "synthetic"; private.mkdir()
        path = private / "probe.stdout"
        cases = [{"streams": [{"time_base": SENTINEL, "start_pts": 0}], "frames": [{"pts": 0}]},
                 {"streams": [{"time_base": "1/30", "start_pts": SENTINEL}], "frames": [{"pts": 0}]},
                 {"streams": [{"time_base": "1/30", "start_pts": 0}], "frames": [{"pts": SENTINEL}]}]
        for data in cases:
            path.write_text(json.dumps(data))
            failure = c.Inconclusive("exact_pts_unavailable")
            with patch.object(c, "decode", side_effect=failure), contextlib.redirect_stdout(io.StringIO()) as console:
                with self.assertRaises(c.Inconclusive) as caught:
                    self._decode_synthetic_fixture_with_pts_evidence(self.root / "source.mp4", private, [])
            self.assertIs(caught.exception, failure)
            self.assertEqual(console.getvalue(), "COMPLETE_OBJECT_SYNTHETIC_PTS unavailable\n")
        with patch.object(c, "decode", side_effect=c.Inconclusive("decode_unsupported")), \
             patch.object(c, "bounded_json") as bounded, contextlib.redirect_stdout(io.StringIO()) as console:
            self.rejects(lambda: self._decode_synthetic_fixture_with_pts_evidence(self.root / "source.mp4", private, []), "decode_unsupported")
        bounded.assert_not_called(); self.assertEqual(console.getvalue(), "")
    def test_real_local_h264_aac_command_path(self):
        ffmpeg, ffprobe = shutil.which("ffmpeg"), shutil.which("ffprobe")
        required = os.environ.get("REQUIRE_COMPLETE_OBJECT_TOOLS") == "true"
        if not (ffmpeg and ffprobe):
            if required: self.fail("Required synthetic FFmpeg tools unavailable")
            self.skipTest("FFmpeg tools unavailable locally; macOS CI must REQUIRE_COMPLETE_OBJECT_TOOLS=true")
        source = self.root / "source.mp4"
        # This fixture is generated locally; there is no locator/network operation.
        command = [ffmpeg, "-nostdin", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=1:duration=601",
                   "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo:d=601", "-c:v", "libx264", "-preset", "ultrafast",
                   "-bf", "0", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "32k", "-use_editlist", "0",
                   "-map_metadata", "-1", "-map_chapters", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact",
                   "-flags:a", "+bitexact", "-metadata", "comment=" + SENTINEL, str(source)]
        result = subprocess.run(command, capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, "Synthetic fixture generation failed")
        # Source metadata is intentionally unsupported. First prove rejection, then
        # remove the synthetic-only terminal moov/udta to create the supported fixture.
        raw = source.read_bytes()
        parser = c.MP4(raw)
        top = parser.children(0, len(raw))
        rebuilt = []
        removed = []
        self.assertEqual(top[-1][0], b"moov", "Synthetic-only normalization requires terminal moov; no source offset rewriting")
        def supported_fixture_children(first, last, depth=1):
            output = []
            for kind, p, q in parser.children(first, last, depth):
                if kind in {b"udta", b"sgpd", b"sbgp"}:
                    removed.append(kind); continue
                if kind in {b"trak", b"mdia", b"minf", b"stbl"}:
                    output.append(box(kind, supported_fixture_children(p, q, depth + 1)))
                else:
                    output.append(box(kind, raw[p:q]))
            return b"".join(output)
        for kind, p, q in top:
            if kind == b"moov":
                rebuilt.append(box(kind, supported_fixture_children(p, q)))
            else:
                rebuilt.append(box(kind, raw[p:q]))
        if removed:
            self.rejects(lambda: c.MP4(raw).validate(), "mp4_unsupported")
        self.assertNotIn(SENTINEL.encode(), b"".join(rebuilt))
        source.write_bytes(b"".join(rebuilt))
        c.validate_mp4(source)
        private = self.root / "software"; private.mkdir()
        requested = [{"targetSeconds": target, "actualPTSValue": target, "actualPTSTimescale": 1} for target in (5, 15, 25, 52)]
        decoded, images = self._decode_synthetic_fixture_with_pts_evidence(source, private, requested)
        self.assertEqual(len(images), 4)
        self.assertTrue(all(row["exactRationalPTSMatch"] for row in decoded["frames"]))
        for raw in images.values():
            self.assertEqual(c.validate_png(raw), raw); self.assertNotIn(SENTINEL.encode(), raw)


if __name__ == "__main__":
    unittest.main()
