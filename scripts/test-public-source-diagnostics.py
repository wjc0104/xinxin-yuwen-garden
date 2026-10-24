"""Offline regression checks for reporting/gating only; never evidence of real playback."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location("diagnostic", Path(__file__).with_name("diagnose-public-source.py"))
diagnostic = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostic)


class Response:
    status = 200

    def __init__(self, payload):
        self.payload = json.dumps(payload).encode()

    def read(self, _):
        return self.payload

    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


class DiagnosticTests(unittest.TestCase):
    def test_http_denial_records_path_status_without_retry(self):
        records = []
        with patch.object(diagnostic, "urlopen", side_effect=HTTPError("https://redacted.invalid/", 412, "denied", {}, None)) as call:
            self.assertIsNone(diagnostic.request("search_article", "/x/web-interface/search/type", {}, records))
        self.assertEqual(call.call_count, 1)
        self.assertEqual(records[0]["http"], 412)
        self.assertEqual(records[0]["reason"], "http_rejected")
        self.assertNotIn("redacted", json.dumps(records))

    def test_partial_search_warning_preserves_strict_playback_gate_and_redacts_urls(self):
        payloads = [
            Response({"code": 0, "data": [{"cid": diagnostic.CID, "page": 2}]}),
            Response({"code": 0, "data": {"quality": 64, "format": "mp4", "durl": [{"url": "https://example.bilivideo.com/video.mp4?token=never-print-this"}]}}),
            Response({"code": 0, "data": {"result": [{"title": "sample", "bvid": diagnostic.BVID}]}}),
            HTTPError("https://redacted.invalid/", 412, "denied", {}, None),
        ]
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "result.json"
            github = Path(folder) / "output"
            stdout = io.StringIO()
            with patch.object(diagnostic, "urlopen", side_effect=payloads) as call, patch.object(sys, "argv", ["probe", "--output", str(output), "--github-output", str(github)]), redirect_stdout(stdout):
                status = diagnostic.main()
            result = json.loads(output.read_text())
            self.assertEqual(status, 0, "Article availability is nonblocking; this is only the diagnostic exit status")
            self.assertFalse(result["all_stages_ok"])
            self.assertTrue(result["playback_ok"])
            self.assertFalse(result["search_ok"])
            playurl = result["stages"][1]
            self.assertEqual(playurl["quality"], 64)
            self.assertEqual(playurl["source_shape"], {
                "data_object": True, "mp4_format": True, "is_preview": False,
                "segments_list": True, "segment_count": 1, "single_segment_object": True,
                "url_string": True, "url_parse_valid": True, "https": True, "allowed_host": True, "has_credentials": False,
            })
            self.assertIn("playback_ok=true", github.read_text())
            self.assertIn("PUBLIC_SEARCH_WARNING", stdout.getvalue())
            self.assertEqual(call.call_count, 4)
            self.assertNotIn("never-print-this", stdout.getvalue() + output.read_text())
            self.assertNotIn("bilivideo.com", stdout.getvalue() + output.read_text())

    def test_playback_denial_blocks_without_attempting_a_different_part(self):
        payloads = [Response({"code": -400}), Response({"code": 0, "data": {"result": []}}), Response({"code": 0, "data": {"result": []}})]
        with tempfile.TemporaryDirectory() as folder, patch.object(diagnostic, "urlopen", side_effect=payloads) as call, patch.object(sys, "argv", ["probe", "--output", str(Path(folder) / "result.json")]), redirect_stdout(io.StringIO()):
            self.assertEqual(diagnostic.main(), 1)
            self.assertEqual(call.call_count, 3, "No playurl or retry when parts are rejected")

    def test_malformed_or_incomplete_media_never_passes(self):
        for data in (None, {}, {"format": "dash"}, {"format": "mp4", "durl": 3}, {"format": "mp4", "durl": [{"url": 3}]}, {"format": "mp4", "durl": [{"url": "https://[invalid"}]}, {"format": "mp4", "is_preview": True, "durl": [{"url": "https://example.bilivideo.com/a"}]}):
            with self.subTest(data=data):
                self.assertFalse(diagnostic.complete_source(data))


    def test_rejected_shape_metadata_preserves_gate_and_redacts_payloads(self):
        media = "https://example.bilivideo.com/private-path.mp4?token=secret-token"
        cases = [
            (None, {"data_object": False}),
            ({}, {"mp4_format": False, "segments_list": False}),
            ({"format": "secret-format", "durl": [{"url": media}]}, {"mp4_format": False, "https": True}),
            ({"format": "mp4", "is_preview": True, "durl": [{"url": media}]}, {"is_preview": True}),
            ({"format": "mp4", "durl": "secret-body"}, {"segments_list": False, "segment_count": 0}),
            ({"format": "mp4", "durl": []}, {"segments_list": True, "segment_count": 0}),
            ({"format": "mp4", "durl": [{"url": media}, {"url": media}]}, {"segment_count": 2, "single_segment_object": False}),
            ({"format": "mp4", "durl": [3]}, {"segment_count": 1, "single_segment_object": False}),
            ({"format": "mp4", "durl": [{"url": media.replace("https:", "http:")}]}, {"https": False, "allowed_host": True}),
            ({"format": "mp4", "durl": [{"url": "https://secret-host.invalid/private-path?token=secret-token"}]}, {"https": True, "allowed_host": False}),
            ({"format": "mp4", "durl": [{"url": media.replace("https://", "https://secret-user:secret-password@")}]}, {"https": True, "allowed_host": True, "has_credentials": True}),
        ]
        for url in (None, 3, [], {}, "https://[invalid"):
            cases.append(({"format": "mp4", "durl": [{"url": url}]}, {"url_parse_valid": False}))
        for data, expected in cases:
            with self.subTest(expected=expected, data_type=type(data).__name__):
                payloads = [
                    Response({"code": 0, "data": [{"cid": diagnostic.CID}]}),
                    Response({"code": 0, "data": data}),
                    Response({"code": 0, "data": {"result": []}}),
                    Response({"code": 0, "data": {"result": []}}),
                ]
                with tempfile.TemporaryDirectory() as folder:
                    output = Path(folder) / "result.json"
                    stdout = io.StringIO()
                    with patch.object(diagnostic, "urlopen", side_effect=payloads) as call, patch.object(sys, "argv", ["probe", "--output", str(output)]), redirect_stdout(stdout):
                        self.assertEqual(diagnostic.main(), 1)
                    result = json.loads(output.read_text())
                    playurl = result["stages"][1]
                    self.assertFalse(result["playback_ok"])
                    self.assertFalse(diagnostic.complete_source(data))
                    self.assertEqual(playurl["reason"], "no_complete_direct_source")
                    self.assertEqual(call.call_count, 4, "Each API is attempted once even when the media shape is rejected")
                    for key, value in expected.items():
                        self.assertEqual(playurl["source_shape"][key], value)
                    self.assertTrue(all(type(value) in (bool, int) for value in playurl["source_shape"].values()))
                    logged = stdout.getvalue() + output.read_text()
                    for secret in ("secret-", "private-path", "bilivideo.com", "token=", "[invalid"):
                        self.assertNotIn(secret, logged)


if __name__ == "__main__":
    unittest.main()
