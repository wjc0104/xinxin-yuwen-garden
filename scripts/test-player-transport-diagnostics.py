"""Focused offline artifact/privacy checks. Swift/Xcode execution still requires exact-head CI."""
from contextlib import redirect_stdout
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("exporter", Path(__file__).with_name("export-player-transport.py"))
exporter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(exporter)


class TransportDiagnosticChecks(unittest.TestCase):
    def export(self, container, result=None, simulator="test-simulator"):
        output = io.StringIO()
        if result is None:
            result = subprocess.CompletedProcess([], 0, str(container), "never-print-private-stderr")
        with patch.dict(os.environ, {"SIMULATOR_ID": simulator}), patch.object(exporter.subprocess, "run", return_value=result) as run, redirect_stdout(output):
            self.assertEqual(exporter.main(), 0)
        self.assertNotIn(str(container), output.getvalue())
        self.assertNotIn("never-print", output.getvalue())
        return run, output.getvalue()

    def test_exports_only_fixed_cache_file_without_printing_contents(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(exporter, "Path", side_effect=lambda path: Path(temporary) / path if path == "build" else Path(path)):
                container = Path(temporary) / "app-private-container"
                source = container / "Library" / "Caches" / exporter.FILE_NAME
                source.parent.mkdir(parents=True)
                source.write_bytes(b'{"event":"checkpoint","sequence":1}\n')
                (source.parent / "credentials.txt").write_text("never-print-secret")
                run, output = self.export(container)
                self.assertNotIn("checkpoint", output)
                self.assertEqual((Path(temporary) / "build" / exporter.FILE_NAME).read_bytes(), source.read_bytes())
                self.assertEqual(len(list((Path(temporary) / "build").iterdir())), 1)
                self.assertEqual(run.call_args.args[0], ["xcrun", "simctl", "get_app_container", "test-simulator", exporter.BUNDLE_ID, "data"])
                self.assertEqual(run.call_args.kwargs["timeout"], 20)

    def test_absent_container_file_simulator_timeout_and_size_are_nonblocking(self):
        with tempfile.TemporaryDirectory() as temporary:
            container = Path(temporary)
            self.export(container, subprocess.CompletedProcess([], 1, "", "never-print-secret"))
            self.export(container)
            run, _ = self.export(container, simulator="")
            run.assert_not_called()
            source = container / "Library" / "Caches" / exporter.FILE_NAME
            source.parent.mkdir(parents=True)
            source.write_bytes(b"x" * (exporter.MAX_BYTES + 1))
            with patch.object(exporter, "Path", side_effect=lambda path: container / path if path == "build" else Path(path)):
                _, output = self.export(container)
                self.assertIn("exceeds its bound", output)
                self.assertFalse((container / "build").exists())
            with patch.dict(os.environ, {"SIMULATOR_ID": "test"}), patch.object(exporter.subprocess, "run", side_effect=subprocess.TimeoutExpired("never-print", 20)), redirect_stdout(io.StringIO()) as output:
                self.assertEqual(exporter.main(), 0)
                self.assertNotIn("never-print", output.getvalue())

    def test_swift_guard_bounds_schema_and_workflow_contract(self):
        sink = (ROOT / "App/PlayerTransportTrace.swift").read_text(encoding="utf-8")
        player = (ROOT / "App/StudyAVPlayer.swift").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/ios-tests.yml").read_text(encoding="utf-8")
        self.assertIn('arguments.contains("--ui-testing") && arguments.contains("--trace-player-transport")', sink)
        self.assertIn('file = enabled ?', sink)
        self.assertIn('guard enabled, let file = file else { return }', sink)
        self.assertIn('static let maxRecords = 2048', sink)
        self.assertIn('static let maxBytes = 512 * 1024', sink)
        self.assertIn('records < Self.maxRecords, bytes < Self.maxBytes', sink)
        self.assertIn('traceLimit', sink)
        self.assertIn('writer.async', sink)
        self.assertNotIn('writer.sync', sink)
        self.assertIn('Data().write(to: file, options: .atomic)', sink)
        self.assertIn('init() { _ = PlayerTransportTrace.shared }', (ROOT / "App/XinxinGardenApp.swift").read_text(encoding="utf-8"))
        state = player.split('var state: [String: Any] =', 1)[1].split('PlayerTransportTrace.shared.record', 1)[0]
        for forbidden in ['url', 'resource', 'identity', 'note', 'token', 'error', 'stack']:
            self.assertNotIn(forbidden, state.lower())
        for required in ['position', 'player', 'item', 'control', 'selected', 'wants', 'applying', 'publishedSeconds', 'pendingSeek']:
            self.assertIn('"' + required + '"', state)
        self.assertIn('let position = currentTime().seconds', player)
        self.assertIn('position.isFinite ? position : -1', player)
        self.assertIn('- name: Export completed result attachments\n        if: always()', workflow)
        self.assertIn('python3 scripts/export-player-transport.py', workflow)
        self.assertIn('build/player-transport.jsonl', workflow)
        self.assertIn('python3 scripts/test-player-transport-diagnostics.py', workflow)


if __name__ == "__main__":
    unittest.main()
