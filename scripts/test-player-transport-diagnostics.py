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
    def test_render_pairs_export_without_trace_and_exclude_unrelated_or_oversize_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "app" / "Library" / "Caches" / exporter.RENDER_DIRECTORY
            source.mkdir(parents=True)
            (source / "g1-s1.json").write_bytes(b'{"sequence":1,"bufferCopied":true}')
            (source / "g1-s1.png").write_bytes(b"bounded-test-png")
            (source / "g1-s2.json").write_bytes(b'{"sequence":2,"bufferCopied":false}')
            (source / "g1-s3.json").write_bytes(b"x" * (exporter.MAX_RENDER_JSON + 1))
            (source / "g1-s4.json").write_bytes(b'{"sequence":4}')
            with (source / "g1-s4.png").open("wb") as stream:
                stream.truncate(exporter.MAX_RENDER_PNG + 1)
            (source / "g1-s8.png").write_bytes(b"orphan-never-export")
            (source / "credentials.txt").write_text("never-print-secret")
            with patch.object(exporter, "Path", side_effect=lambda path: root / path if path == "build" else Path(path)):
                _, output = self.export(root / "app")
            destination = root / "build" / exporter.RENDER_DIRECTORY
            self.assertEqual(sorted(path.name for path in destination.iterdir()),
                             ["g1-s1.json", "g1-s1.png", "g1-s2.json", "g1-s4.json"])
            self.assertNotIn("sequence", output)
            self.assertNotIn("never-print", output)

    def test_render_sample_count_is_bounded_and_ordinary_launch_remains_output_free(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / exporter.RENDER_DIRECTORY
            source.mkdir()
            for generation in [1, 2]:
                for sequence in range(1, 9):
                    (source / f"g{generation}-s{sequence}.json").write_bytes(b"{}")
            with patch.object(exporter, "Path", side_effect=lambda path: root / path if path == "build" else Path(path)), redirect_stdout(io.StringIO()) as output:
                exporter.export_render(root)
            self.assertIn("count exceeds its bound", output.getvalue())
            self.assertFalse((root / "build").exists())
        sink = (ROOT / "App/SameItemRenderDiagnostic.swift").read_text(encoding="utf-8")
        ui = (ROOT / "UITests/GardenUITests.swift").read_text(encoding="utf-8")
        workflow = (ROOT / ".github/workflows/ios-tests.yml").read_text(encoding="utf-8")
        self.assertTrue(sink.startswith("#if DEBUG\n"))
        self.assertIn('arguments.contains("--ui-testing"), arguments.contains(flag)', sink)
        self.assertIn('player.currentItem === item', sink)
        self.assertIn('attachment.video?.retainedController === attachment', sink)
        self.assertIn('Self.sampleCount < Self.maxSamples', sink)
        self.assertIn('item?.remove(output)', sink)
        for forbidden in ['player.seek(', 'player.play(', 'player.pause(', 'AVPlayer(playerItem:', 'URLRequest', 'resource.url']:
            self.assertNotIn(forbidden, sink)
        self.assertIn('checkVideoPlaybackFullScreenLandscape(sameItemDiagnostics: false)', ui)
        self.assertIn('if sameItemDiagnostics { app.launchArguments.append("--same-item-render-diagnostics") }', ui)
        self.assertLess(ui.index('phase: "initial-inline-playing-'), ui.index('let entering ='))
        self.assertIn('initialPictures.allSatisfy { $0 }', ui)
        self.assertIn('decodedReceipt=\\(decodedReceipt)', ui)
        self.assertIn('screenshotStartUptime=', ui)
        self.assertIn('same_item_render_diagnostics:', workflow)
        self.assertIn('build/same-item-render/', workflow)

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

    def test_retained_stock_controller_and_production_presentation(self):
        owner = (ROOT / "App/NativeStudyPlayer.swift").read_text(encoding="utf-8")
        fullscreen = (ROOT / "App/FullScreenStudyPlayer.swift").read_text(encoding="utf-8")
        inline = (ROOT / "App/VideoStudyView.swift").read_text(encoding="utf-8")
        native = (ROOT / "AppTests/NativePlaybackTests.swift").read_text(encoding="utf-8")
        ui = (ROOT / "UITests/GardenUITests.swift").read_text(encoding="utf-8")
        self.assertLess(owner.index('retainedController = RetainedStudyPlayerController(video: self, player: value)'),
                        owner.index('player = value'))
        self.assertEqual(fullscreen.count('AVPlayerViewController()'), 1)
        self.assertEqual(fullscreen.count('controller.player = player'), 1)
        self.assertIn('if video.player != nil { NativeInlinePlayer(video: video) }', inline)
        self.assertNotIn('VideoPlayer(', inline + fullscreen + native)
        self.assertIn('next?.register(self)', fullscreen)
        self.assertIn('attachment?.refresh(self)', fullscreen)
        self.assertNotIn('attachment?.end(self)', fullscreen.split('override func viewDidAppear(', 1)[1].split('func bind(', 1)[0])
        self.assertIn('guard fullscreenHost === host else { return }', fullscreen)
        for evidence in ['host.addChild(controller)', 'host.view.addSubview(controller.view)',
                         'controller.didMove(toParent: host)', 'controller.willMove(toParent: nil)',
                         'controller.view.removeFromSuperview()', 'controller.removeFromParent()',
                         'guard fullscreenHost == nil else { return }',
                         'inlineHost.view.window != nil', 'controller.parent === owner',
                         '"native-video-player"', '"fullscreen-native-player"',
                         '"fullscreen-video-render-status"', 'controller.isReadyForDisplay']:
            self.assertIn(evidence, fullscreen)
        for obsolete in ['FullScreenRestoration', 'suspendedRestoration', 'restorationWatchdog',
                         'bindFullScreenPlayer', 'preservingPausedBinding']:
            self.assertNotIn(obsolete, owner + fullscreen)
        for evidence in ['try await assertFractionalFullScreenBinding(video, player: player, item: item)',
                         'NativeInlinePlayer(video: video)', 'FullScreenStudyPlayer(video: video)',
                         'CMTime(seconds: 21.625, preferredTimescale: 600)',
                         'video.retainedController === retained', 'controller.player === player',
                         'player.currentItem === item', 'accuracy: 0.005',
                         'let staleInline = StudyPlayerHostController(role: .inline)',
                         'assertCompactPageSheetKeepsFullscreenOwner(',
                         'assertSupersededFullscreenHostCannotReclaim(']:
            self.assertIn(evidence, native)
        for evidence in ['paused-inline-before-entry', 'paused-fullscreen-before-2x',
                         'paused-landscape-right', 'paused-landscape-left',
                         'paused-inline-after-dismissal', 'Double(before), accuracy: 1)']:
            self.assertIn(evidence, ui)
        self.assertIn('fullscreenSpeed.tap()\n        app.buttons["video-speed-option-2"].tap()',
                      ui.split('let nativeFrame =', 1)[1].split('phase: "paused-landscape-right"', 1)[0])

    def test_native_intent_supersedes_obsolete_application_seek(self):
        owner = (ROOT / "App/NativeStudyPlayer.swift").read_text(encoding="utf-8")
        player = (ROOT / "App/StudyAVPlayer.swift").read_text(encoding="utf-8")
        native = (ROOT / "AppTests/NativePlaybackTests.swift").read_text(encoding="utf-8")
        self.assertIn('let item = StudyAVPlayerItem(asset: asset)', owner)
        self.assertIn('item.studyPlayer = value', owner)
        self.assertIn('pendingSeekIntentRevision = (player as? StudyAVPlayer)?.intentRevision', owner)
        self.assertIn('guard (player as? StudyAVPlayer)?.intentRevision == issuedRevision else { return }', owner)
        self.assertIn('player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: completion)', owner)
        self.assertIn('player?.currentItem === item, self.pendingSeek == seekToken', owner)
        self.assertEqual(player.count('override func seek('), 9, "All six player and three item public seek overloads participate")
        self.assertIn('override func cancelPendingSeeks()', player)
        self.assertIn('weak var studyPlayer: StudyAVPlayer?', player)
        for entry in ['override func play()', 'override func pause()', 'override var rate:',
                      'override func playImmediately(', 'override func setRate(']:
            command = player.split(entry, 1)[1].split('\n    }', 1)[0]
            self.assertIn('commandRevision = UUID()', command)
        race = native.split('private func assertNativeCommandsSupersedeAppSeek(', 1)[1].split('private func waitForPresentation(', 1)[0]
        overlap = race.split('video.seek(to: target)', 1)[1].split('let newerRevision = native.intentRevision', 1)[0]
        self.assertNotIn('await ', overlap)
        for evidence in ['XCTAssertNotNil(video.pendingSeek', 'player.seek(to: newerTarget',
                         'item.seek(to: newerTarget', 'player.play(); player.pause()']:
            self.assertIn(evidence, overlap)
        self.assertIn('XCTAssertEqual(native.intentRevision, newerRevision)', race)
        self.assertIn('video.$seconds.dropFirst().sink', race)
        self.assertIn('XCTAssertFalse(published.contains', race)
        self.assertIn('abs($0.actual - newerTarget.seconds) <= 0.05', race)
if __name__ == "__main__":
    unittest.main()
