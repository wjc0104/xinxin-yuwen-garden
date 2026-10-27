#!/usr/bin/env python3
"""Offline source-contract checks, not Swift compilation or native runtime proof."""
import hashlib
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASELINE_SHA256 = "0fccf13f3d83115dde0c6ddc4d1016c3424c1b260aec2e72fecb2a15ba9df632"
SETUP_SHA256 = "83b9a7a0cef658f0b88b229f43dd4c8d6b57c0f536949d526d9f13e286665540"
PROJECT_SHA256 = "eb5440931faed95b9d64ca046bfb3571a001a8729bfe76fa21ba5adbf802cbeb"
ORIGINAL_HEADER = '''    func testPlainAVPlayerSharedAssetDecodedOutputControl() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GARDEN_SAME_ITEM_RENDER_DIAGNOSTICS"] == "1", "Diagnostic-only plain decoded-output control")
'''
EXTRACTED_HEADER = ORIGINAL_HEADER + '''        try await capturePlainDecodedOutputControl()
    }
    func testCompleteObjectSameBytesDecodedOutputControl() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GARDEN_COMPLETE_OBJECT_SAME_BYTES"] == "1", "Diagnostic-only complete-object decoded-output control")
        try await capturePlainDecodedOutputControl(localContext: CompleteObjectTestContext())
    }
    private func capturePlainDecodedOutputControl(localContext: CompleteObjectTestContext? = nil) async throws {
'''
LOCAL_TAGS = ("summary-finalize", "result-write", "png-write", "source-branch", "source-end", "pts-flags")


def remove_local_blocks(source):
    for tag in LOCAL_TAGS:
        pattern = rf"^[ ]*// COMPLETE_OBJECT_LOCAL_BEGIN {tag}\n.*?^[ ]*// COMPLETE_OBJECT_LOCAL_END {tag}\n"
        source, count = re.subn(pattern, "", source, flags=re.M | re.S)
        if count != 1:
            raise AssertionError(f"Expected one bounded local block: {tag}")
    if "COMPLETE_OBJECT_LOCAL_" in source:
        raise AssertionError("Unrecognized local insertion")
    return source


def reconstruct_remote(source):
    if source.count(EXTRACTED_HEADER) != 1:
        raise AssertionError("Wrapper/extraction differs from approved mechanical edit")
    return remove_local_blocks(source.replace(EXTRACTED_HEADER, ORIGINAL_HEADER, 1))


class CompleteObjectSwiftContract(unittest.TestCase):
    def setUp(self):
        self.native = (ROOT / "AppTests/NativePlaybackTests.swift").read_text(encoding="utf-8")
        self.helper = (ROOT / "AppTests/CompleteObjectTestContext.swift").read_text(encoding="utf-8") if (ROOT / "AppTests/CompleteObjectTestContext.swift").exists() else ""

    def test_remote_reconstruction_including_all_other_methods_matches_frozen_head(self):
        restored = reconstruct_remote(self.native)
        self.assertEqual(hashlib.sha256(restored.replace("\n", "\r\n").encode()).hexdigest(), BASELINE_SHA256)
        a = restored.index("        var resource = StudyResource", restored.index("    func testPlain"))
        b = restored.index("        let asset = try XCTUnwrap(sharedAsset", a)
        self.assertEqual(hashlib.sha256(restored[a:b].replace("\n", "\r\n").encode()).hexdigest(), SETUP_SHA256)

    def test_reconstruction_detects_changed_gate_and_defer_lifetime(self):
        for old, new in [("softDeadline = started + 130", "softDeadline = started + 131"),
                         ("after <= target + 0.75", "after <= target + 0.76"),
                         ("defer { loader.pause() }", "loader.pause()")]:
            with self.subTest(old=old):
                changed = reconstruct_remote(self.native.replace(old, new, 1))
                self.assertNotEqual(hashlib.sha256(changed.replace("\n", "\r\n").encode()).hexdigest(), BASELINE_SHA256)

    def test_new_scheme_is_independent_explicit_opt_in_only(self):
        project = (ROOT / "project.yml").read_text(encoding="utf-8")
        self.assertIn("  XinxinGardenCompleteObjectDiagnostics:\n", project)
        original, new = project.split("  XinxinGardenCompleteObjectDiagnostics:\n", 1)
        self.assertEqual(hashlib.sha256(original.replace("\n", "\r\n").encode()).hexdigest(), PROJECT_SHA256)
        self.assertNotIn("GARDEN_COMPLETE_OBJECT_SAME_BYTES", original)
        self.assertEqual(new, "    build:\n      targets:\n        XinxinGarden: all\n    test:\n      targets: [GardenAppTests]\n      environmentVariables:\n        GARDEN_COMPLETE_OBJECT_SAME_BYTES: '1'\n")

    def test_local_capture_export_hash_and_result_order_preserves_partial_frames(self):
        # Dropping local source verification or moving it before export must fail.
        blocks = {}
        for tag in LOCAL_TAGS:
            match = re.search(rf"// COMPLETE_OBJECT_LOCAL_BEGIN {tag}\n(.*?)^[ ]*// COMPLETE_OBJECT_LOCAL_END {tag}", self.native, re.M | re.S)
            self.assertIsNotNone(match, tag)
            blocks[tag] = match.group(1)
        self.assertIn("localContext.prepare(softDeadline: softDeadline)", blocks["source-branch"])
        self.assertIn("if let localContext = localContext", blocks["source-branch"])
        self.assertTrue(blocks["source-branch"].rstrip().endswith("} else {"))
        self.assertIn("localContext.finalize(&summary)", blocks["summary-finalize"])
        self.assertIn("localContext.writeResult(summary)", blocks["result-write"])
        self.assertIn("localContext.writePNG(png, name: snapshot.name)", blocks["png-write"])
        self.assertIn('"actualPTSFlags": actual.flags.rawValue', blocks["pts-flags"])
        self.assertIn('"actualPTSEpoch": actual.epoch', blocks["pts-flags"])
        self.assertEqual(blocks["source-end"].strip(), "}")
        for tag in ("summary-finalize", "result-write", "png-write"):
            self.assertTrue(blocks[tag].lstrip().startswith("if let localContext = localContext"), tag)
        self.assertTrue(blocks["source-branch"].lstrip().startswith("if let localContext = localContext"))
        self.assertTrue(blocks["pts-flags"].lstrip().startswith("if localContext != nil"))
        self.assertIn('summary["endedUptime"] = finite(ProcessInfo.processInfo.systemUptime)\n            // COMPLETE_OBJECT_LOCAL_BEGIN summary-finalize', self.native)
        self.assertIn('// COMPLETE_OBJECT_LOCAL_END summary-finalize\n            let encoded =', self.native)
        self.assertIn('frames[snapshot.index]["exportState"] = "attached"\n                        // COMPLETE_OBJECT_LOCAL_BEGIN png-write', self.native)
        self.assertIn('weak var loaderWitness: NativeStudyPlayer?\n        // COMPLETE_OBJECT_LOCAL_BEGIN source-branch', self.native)
        self.assertIn('// COMPLETE_OBJECT_LOCAL_END source-branch\n        do {\n            let loader = NativeStudyPlayer()', self.native)
        self.assertLess(self.native.index("localContext.finalize(&summary)"), self.native.index("localContext.writeResult(summary)"))
        self.assertLess(self.native.index("localContext.writeResult(summary)"), self.native.index('summary["exportStartedUptime"] ='))

    def test_helper_fail_closed_guards_and_incremental_io_exist(self):
        for required in ['import CryptoKit', 'import Darwin', 'O_NOFOLLOW', 'O_DIRECTORY', 'AT_SYMLINK_NOFOLLOW',
                         'status.st_nlink == 1', 'mode_t(0o400)', 'mode_t(0o700)',
                         'CFGetTypeID(number) != CFBooleanGetTypeID()', 'Set(object.keys) == Set(["schema", "nonce", "bytes", "sha256"])',
                         'UUID(uuidString: nonce)?.uuidString.lowercased() == nonce',
                         '64 * 1024 * 1024', '64 * 1024', '4096', '16 * 1024',
                         'SHA256()', 'hash.update(data: chunk)', 'sourceHashVerified',
                         'fileBefore', 'fileAfter', 'localCompleteObjectDecodedOutput',
                         'O_EXCL', 'prepare(softDeadline:', 'verifySource()', 'writeResult(', 'writePNG(']:
            self.assertIn(required, self.helper)
        for forbidden in ['mappedIfSafe', 'alwaysMapped', 'Data(contentsOf:', 'URLSession', 'URLRequest', 'http://', 'https://',
                          'localizedDescription', 'String(describing: error)', 'print(']:
            self.assertNotIn(forbidden, self.helper)
        self.assertIn('let leaves: Set<String> = ["plain-05.png", "plain-15.png", "plain-25.png", "plain-paused52.png"]', self.helper)

    def test_cache_path_replacement_duplicate_manifest_keys_and_oversize_mutation_are_guarded(self):
        for required in ['Darwin.lstat(cachesURL.path, &namedCaches)',
                         'text.components(separatedBy: $0).count == 2',
                         'min($0.count, manifest.bytes - total + 1)']:
            self.assertIn(required, self.helper)


if __name__ == "__main__":
    unittest.main()
