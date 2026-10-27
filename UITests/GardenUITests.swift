import XCTest
import UIKit

final class GardenUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCUIDevice.shared.orientation = .portrait
    }

    func testPoetryLoginAndReturnKeepReaderActionsAndNotesWithoutRemoteLogin() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-offline-reader"]
        app.launch()
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-04"].tap()
        let picker = app.scrollViews["lesson-category-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.swipeLeft()
        app.buttons["课文解读"].firstMatch.tap()
        let original = app.buttons["resource-curated-text-7u-04-7dbbc1cc5964f7a5"]
        XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()

        let options = app.buttons["poetry-reading-options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "poetry-reading-options").count, 1)
        XCTAssertTrue(options.isHittable)
        // AX CGRect subtraction can report 43.999999999999986 for a 44pt target.
        XCTAssertGreaterThanOrEqual(options.frame.width, 44 - 0.001)
        XCTAssertGreaterThanOrEqual(options.frame.height, 44 - 0.001)
        options.tap()
        let login = app.buttons["poetry-site-login"]
        let restore = app.buttons["poetry-return-original"]
        XCTAssertTrue(login.waitForExistence(timeout: 5))
        XCTAssertEqual(login.label, "原站登录")
        XCTAssertTrue(!restore.exists || !restore.isEnabled, "Return must be unavailable while already on the original article")
        app.buttons["poetry-reading-guidance"].tap()
        let guidance = app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "原站已公开提供的全文会直接显示")).firstMatch
        XCTAssertTrue(guidance.waitForExistence(timeout: 3))
        XCTAssertTrue(guidance.label.contains("账号功能可选"))
        app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.staticTexts["古文岛 · 原文署名见页面"].exists)
        XCTAssertTrue(app.buttons["open-in-browser"].exists)
        XCTAssertTrue(app.buttons["web-quote-selection"].exists)
        options.tap(); login.tap()
        let inlineRestore = app.buttons["poetry-return-inline"]
        XCTAssertTrue(inlineRestore.waitForExistence(timeout: 3), "The actual reader action must call the attached controller even when network navigation is cancelled")
        options.tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 3))
        XCTAssertTrue(restore.isEnabled)
        XCTAssertTrue(restore.isHittable)
        restore.tap()
        XCTAssertFalse(inlineRestore.exists, "The actual menu return action must restore the original article state")
        options.tap()
        XCTAssertTrue(login.waitForExistence(timeout: 3))
        XCTAssertTrue(!restore.exists || !restore.isEnabled, "Menu return must make the return action unavailable again")
        login.tap()
        XCTAssertTrue(inlineRestore.waitForExistence(timeout: 3))
        options.tap()
        XCTAssertTrue(restore.waitForExistence(timeout: 3)); XCTAssertTrue(restore.isEnabled)
        app.buttons["poetry-reading-guidance"].tap()
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "账号功能及登录结果由原站决定")).firstMatch.waitForExistence(timeout: 3))
        app.alerts.buttons["知道了"].tap()
        shot("17-诗词原站登录与返回入口")

        // The note sheet remains the existing reader's sheet while login navigation is pending.
        app.buttons["study-note"].tap()
        let note = app.textViews["note-input"]
        XCTAssertTrue(note.waitForExistence(timeout: 4)); note.tap(); note.typeText("poetry reader draft")
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(note.value as? String, "poetry reader draft")
        app.buttons["save-note"].tap()
        XCTAssertTrue(inlineRestore.waitForExistence(timeout: 4)); inlineRestore.tap()
        XCTAssertFalse(inlineRestore.exists)
        options.tap()
        XCTAssertTrue(login.waitForExistence(timeout: 3))
        XCTAssertTrue(!restore.exists || !restore.isEnabled, "Return must be unavailable while already on the original article")
        XCTAssertTrue(login.isEnabled)
        app.buttons["poetry-reading-guidance"].tap(); app.alerts.buttons["知道了"].tap()
        XCTAssertTrue(app.buttons["web-quote-selection"].exists)
        XCTAssertTrue(app.buttons["open-in-browser"].exists)
        shot("18-诗词返回原文保留阅读操作")
        app.tabBars.buttons["我的"].tap()
        app.buttons["我的笔记与收藏"].tap()
        XCTAssertTrue(app.staticTexts["poetry reader draft"].firstMatch.waitForExistence(timeout: 5))
    }

    func testPoetryReaderPortraitBothLandscapesAndBackKeepReadableSpace() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-offline-reader", "--ui-testing-poetry-layout", "--ui-testing-reader-static-transitions"]
        app.launch()
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-04"].tap()
        let picker = app.scrollViews["lesson-category-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.swipeLeft()
        app.buttons["课文解读"].firstMatch.tap()
        let original = app.buttons["resource-curated-text-7u-04-7dbbc1cc5964f7a5"]
        XCTAssertTrue(original.waitForExistence(timeout: 5)); original.tap()
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.staticTexts["响应式阅读测试"].waitForExistence(timeout: 5))
        let phases: [(String, UIDeviceOrientation)] = [("portrait", .portrait), ("landscape-left", .landscapeLeft), ("landscape-right", .landscapeRight), ("portrait-return", .portrait)]
        for (phase, orientation) in phases {
            XCUIDevice.shared.orientation = orientation
            let landscape = orientation.isLandscape
            let reflowed = NSPredicate { _, _ in
                let frame = app.frame, reader = web.frame
                return (frame.width > frame.height) == landscape && reader.width >= frame.width - 120 && reader.height >= frame.height * (landscape ? 0.4 : 0.6)
            }
            wait(for: [XCTNSPredicateExpectation(predicate: reflowed, object: nil)], timeout: 8)
            XCTAssertTrue(web.staticTexts["响应式阅读测试"].exists, phase)
            XCTAssertTrue(app.buttons["web-quote-selection"].isHittable, phase)
            XCTAssertTrue(app.buttons["study-note"].isHittable, phase)
            XCTAssertTrue(app.buttons["open-in-browser"].isHittable, phase)
            let options = app.buttons["poetry-reading-options"]
            let geometry = XCTAttachment(string: "\(phase): app=\(app.frame), web=\(web.frame), options=\(options.frame), optionsHittable=\(options.isHittable)")
            geometry.name = "poetry-native-geometry-" + phase; geometry.lifetime = .keepAlways; add(geometry)
            XCTAssertEqual(app.buttons.matching(identifier: "poetry-reading-options").count, 1, phase)
            XCTAssertTrue(options.isHittable, phase)
            // Allow only subpixel arithmetic rounding; hit testing remains mandatory.
            XCTAssertGreaterThanOrEqual(options.frame.width, 44 - 0.001, phase)
            XCTAssertGreaterThanOrEqual(options.frame.height, 44 - 0.001, phase)
            shot("poetry-layout-" + phase)
            options.tap()
            XCTAssertTrue(app.buttons["poetry-site-login"].exists, phase)
            XCTAssertTrue(app.buttons["poetry-site-login"].isHittable, phase)
            app.buttons["poetry-reading-guidance"].tap()
            XCTAssertTrue(app.alerts["阅读说明"].waitForExistence(timeout: 3))
            app.alerts.buttons["知道了"].tap()
        }
    }

    func testTextSelectionHighlightsAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-02"].tap()
        openOutlineCategory(app)
        app.buttons["resource-curated-guide-7u-02"].tap()
        let text = app.textViews.firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.coordinate(withNormalizedOffset: CGVector(dx: 0.09, dy: 0)).withOffset(CGVector(dx: 0, dy: 14)).press(forDuration: 1.2)
        let highlight = app.buttons["划重点"].firstMatch
        XCTAssertTrue(highlight.waitForExistence(timeout: 5), "Selecting text must expose an actionable highlight command")
        highlight.tap()
        XCTAssertTrue(app.staticTexts["已保存 1 处重点"].waitForExistence(timeout: 5))
        shot("11-正文真实选词划重点")
        app.terminate(); app.launch()
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-02"].tap()
        openOutlineCategory(app)
        app.buttons["resource-curated-guide-7u-02"].tap()
        XCTAssertTrue(app.staticTexts["已保存 1 处重点"].waitForExistence(timeout: 5))
        shot("12-重启后正文高亮")
    }
    func testVideoStudyTimestamp() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: nil)
        wait(for: [portrait], timeout: 8)
        XCTAssertGreaterThan(app.frame.height, app.frame.width, "Timestamp input requires a restored portrait app")
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-02"].tap()
        let video = app.buttons["resource-curated-7u-02-BV1eUAieoEZd-2"]
        XCTAssertTrue(video.waitForExistence(timeout: 5)); video.tap()
        XCTAssertTrue(app.buttons["边看边记"].waitForExistence(timeout: 15), "The visible note affordance must be an actual action")
        XCTAssertEqual(app.webViews.count, 0, "Online video must use the native player rather than a webpage")
        XCTAssertTrue(app.buttons["study-note"].exists)
        shot("09-视频学习与笔记")
        app.buttons["边看边记"].tap()
        let note = app.textViews["video-note-input"]; XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        if let old = note.value as? String, !old.isEmpty { note.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        note.typeText("test video timestamp")
        let time = app.textFields["分:秒 或 时:分:秒"]
        time.tap()
        let old = (time.value as? String) ?? ""
        if !old.isEmpty && old != "分:秒 或 时:分:秒" { time.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        time.typeText("03:25")
        app.buttons["收起"].tap()
        app.buttons["边看边记"].tap()
        XCTAssertEqual(time.value as? String, "03:25", "Reopening a draft must preserve its original time anchor")
        XCTAssertEqual(note.value as? String, "test video timestamp")
        app.terminate(); app.launch()
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.height > app.frame.width
        }, object: nil)], timeout: 8)
        XCTAssertGreaterThan(app.frame.height, app.frame.width, "Timestamp relaunch requires a restored portrait app")
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-02"].tap(); video.tap()
        app.buttons["边看边记"].tap()
        XCTAssertEqual(time.value as? String, "03:25", "An unfinished draft must survive relaunch")
        XCTAssertEqual(note.value as? String, "test video timestamp")
        note.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        shot("13-视频与内联笔记草稿")
        app.buttons["收起"].tap()
        app.buttons["边看边记"].tap()
        app.buttons["video-save-note"].tap()
        XCTAssertTrue(app.staticTexts["03:25"].firstMatch.waitForExistence(timeout: 5))
        shot("10-视频时间笔记")
    }
    func testVideoPlaybackFullScreenLandscape() throws {
        try checkVideoPlaybackFullScreenLandscape(sameItemDiagnostics: false)
    }
    func testVideoPlaybackFullScreenLandscapeWithSameItemDiagnostics() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GARDEN_SAME_ITEM_RENDER_DIAGNOSTICS"] == "1",
                          "Requires explicit XinxinGardenRenderDiagnostics test scheme opt-in")
        let optIn = XCTAttachment(string: "testRunnerOptIn=1; explicit same-item render experiment")
        optIn.name = "same-item-render-test-runner-opt-in"; optIn.lifetime = .keepAlways; add(optIn)
        try checkVideoPlaybackFullScreenLandscape(sameItemDiagnostics: true)
    }
    private func checkVideoPlaybackFullScreenLandscape(sameItemDiagnostics: Bool) throws {
        continueAfterFailure = false
        try checkRenderedVideoImageCoordinates()
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--trace-player-transport", "--legacy-player-transport"]
        if sameItemDiagnostics { app.launchArguments.append("--same-item-render-diagnostics") }
        app.launch()
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-02"].tap()
        app.buttons["resource-curated-7u-02-BV1eUAieoEZd-2"].tap()
        let play = app.buttons["video-play-pause"]
        let error = app.staticTexts["video-source-error"]
        let readyOrError = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in play.isEnabled || error.exists }, object: nil)
        wait(for: [readyOrError], timeout: 70)
        XCTAssertFalse(error.exists, error.exists ? error.label : "")
        XCTAssertTrue(play.isEnabled)
        let speed = app.buttons["video-speed"]
        XCTAssertEqual(speed.label, "倍速 1×")
        speed.tap()
        for value in ["0.5", "0.75", "1", "1.25", "1.5", "2"] {
            XCTAssertTrue(app.buttons["video-speed-option-" + value].exists)
        }
        app.buttons["video-speed-option-1.5"].tap()
        XCTAssertEqual(play.label, "播放", "Changing speed while paused cannot start playback")
        XCTAssertEqual(speed.label, "倍速 1.5×")
        if sameItemDiagnostics {
            // Initial paused evidence may be an opening frame; it is explicitly not an informative-image gate.
            _ = try assertRenderedVideo(app, playerID: "native-video-player", phase: "initial-inline-paused-diagnostic",
                                        enforceImageGate: false, sameItemCapture: true)
        }
        play.tap()
        let position = app.staticTexts["video-position"]
        let moving = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label != %@ AND label != %@", "--:--", "00:00", ""), object: position)
        wait(for: [moving], timeout: 25)
        XCTAssertEqual(speed.label, "倍速 1.5×")
        let initial = try XCTUnwrap(videoSeconds(position.label))
        var initialPictures: [Bool] = []
        for offset in [0, 2, 4] {
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                (self.videoSeconds(position.label) ?? -1) >= initial + offset
            }, object: nil)], timeout: 15)
            XCTAssertEqual(play.label, "暂停", "Initial picture checkpoints must observe real running playback")
            initialPictures.append(try assertRenderedVideo(app, playerID: "native-video-player",
                phase: "initial-inline-playing-\(offset)", enforceImageGate: false, sameItemCapture: sameItemDiagnostics))
        }
        // Collect all three actual observations before failing; never retry until a green picture improves.
        XCTAssertTrue(initialPictures.allSatisfy { $0 }, "Initial running displayed-video gates failed: \(initialPictures)")
        // A real running item must advance across presentation and dismissal at the selected rate.
        let entering = try XCTUnwrap(videoSeconds(position.label))
        app.buttons["video-fullscreen"].tap()
        let runningExit = app.buttons["video-exit-fullscreen"]
        XCTAssertTrue(runningExit.waitForExistence(timeout: 5))
        let runningPosition = app.staticTexts["fullscreen-video-position"]
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (self.videoSeconds(runningPosition.label) ?? -1) >= entering + 2
        }, object: nil)], timeout: 15)
        XCTAssertEqual(app.buttons["fullscreen-video-speed"].label, "倍速 1.5×")
        // Exercise the stock AVKit transport controls, not just the app's external play button.
        let native = app.descendants(matching: .any)["fullscreen-native-player"].firstMatch
        try tapNativeTransportButton(native, expecting: "(暂停|Pause)(播放|视频| Video| Playback)?")
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已暂停"), object: runningPosition)], timeout: 5)
        let stockPausedTime = try XCTUnwrap(videoSeconds(runningPosition.label))
        app.buttons["fullscreen-video-speed"].tap()
        app.buttons["video-speed-option-1.5"].tap()
        XCTAssertEqual(runningPosition.value as? String, "已暂停", "Selecting speed after stock AVKit pause must remain paused")
        try tapNativeTransportButton(native, expecting: "(播放|继续播放|Play|Resume)(视频| Video| Playback)?")
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "播放中 · 实际倍速 1.5"), object: runningPosition)], timeout: 5)
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (self.videoSeconds(runningPosition.label) ?? -1) >= stockPausedTime + 2
        }, object: nil)], timeout: 15)
        XCTAssertEqual(app.buttons["fullscreen-video-speed"].label, "倍速 1.5×")
        let exiting = try XCTUnwrap(videoSeconds(runningPosition.label))
        runningExit.tap()
        XCTAssertTrue(app.buttons["video-fullscreen"].waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "暂停", "Dismissal must preserve running playback")
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (self.videoSeconds(position.label) ?? -1) >= exiting + 2
        }, object: nil)], timeout: 15)
        XCTAssertEqual(speed.label, "倍速 1.5×")
        play.tap() // Also retain the paused/draft transition case.
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "播放"), object: play)
        wait(for: [paused], timeout: 5)
        app.buttons["边看边记"].tap()
        let note = app.textViews["video-note-input"]
        app.buttons["取当前时间"].tap()
        let time = app.textFields["分:秒 或 时:分:秒"]
        let captured = try XCTUnwrap(time.value as? String)
        XCTAssertNotEqual(captured, "", "Notes must capture the actual player time")
        let before = try XCTUnwrap(videoSeconds(position.label))
        XCTAssertEqual(videoSeconds(captured), before, "The draft anchor must match the paused native player's time")
        note.tap()
        if let old = note.value as? String, !old.isEmpty { note.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        note.typeText("fullscreen draft")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        try assertRenderedVideo(app, playerID: "native-video-player", phase: "paused-inline-before-entry")
        app.buttons["video-fullscreen"].tap()
        let exit = app.buttons["video-exit-fullscreen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        let fullscreenSpeed = app.buttons["fullscreen-video-speed"]
        XCTAssertEqual(fullscreenSpeed.label, "倍速 1.5×")
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已暂停"), object: runningPosition)], timeout: 5)
        try assertRenderedVideo(app, playerID: "fullscreen-native-player", phase: "paused-fullscreen-before-2x")
        shot("17-全屏倍速菜单点击前")
        fullscreenSpeed.tap(); app.buttons["video-speed-option-2"].tap()
        XCTAssertEqual(fullscreenSpeed.label, "倍速 2×")
        XCUIDevice.shared.orientation = .landscapeLeft
        // Device landscapeLeft maps to interface landscapeRight (home indicator on the opposite side).
        let orientation = app.descendants(matching: .any)["fullscreen-interface-orientation"].firstMatch
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "landscapeRight"), object: orientation)], timeout: 8)
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        wait(for: [landscape], timeout: 8)
        let nativeFrame = app.descendants(matching: .any)["fullscreen-native-player"].firstMatch.frame
        XCTAssertGreaterThan(nativeFrame.width, nativeFrame.height, "The native video controller itself must occupy landscape")
        XCTAssertGreaterThan(nativeFrame.width, app.frame.width * 0.9)
        // Open the real speed sheet in compact height; dismissing it must keep this fullscreen owner.
        fullscreenSpeed.tap()
        app.buttons["video-speed-option-2"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["fullscreen-native-player"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(fullscreenSpeed.label, "倍速 2×")
        XCTAssertEqual(runningPosition.value as? String, "已暂停")
        try assertRenderedVideo(app, playerID: "fullscreen-native-player", phase: "paused-landscape-right")
        shot("15-原生视频横屏全屏")
        XCUIDevice.shared.orientation = .landscapeRight
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "landscapeLeft"), object: orientation)], timeout: 8)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        let secondNativeFrame = app.descendants(matching: .any)["fullscreen-native-player"].firstMatch.frame
        XCTAssertGreaterThan(secondNativeFrame.width, secondNativeFrame.height)
        XCTAssertGreaterThan(secondNativeFrame.width, app.frame.width * 0.9)
        try assertRenderedVideo(app, playerID: "fullscreen-native-player", phase: "paused-landscape-left")
        exit.tap()
        XCTAssertTrue(app.buttons["video-fullscreen"].waitForExistence(timeout: 5))
        XCTAssertEqual(play.label, "播放", "Exiting must respect the user's paused state")
        XCTAssertEqual(speed.label, "倍速 2×", "Fullscreen speed selection must survive exit")
        XCTAssertEqual(Double(try XCTUnwrap(videoSeconds(position.label))), Double(before), accuracy: 1)
        XCTAssertEqual(note.value as? String, "fullscreen draft")
        XCTAssertEqual(time.value as? String, captured)
        XCUIDevice.shared.orientation = .portrait
        let portrait = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.height > app.frame.width }, object: nil)
        wait(for: [portrait], timeout: 8)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "The note editor's focus returns after fullscreen")
        try assertRenderedVideo(app, playerID: "native-video-player", phase: "paused-inline-after-dismissal")
        shot("16-退出全屏保留草稿与键盘")
    }
    func testSearchStudyNotesAndChineseSchedule() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        XCTAssertTrue(app.tabBars.buttons["主页"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.buttons["小花园"].exists)
        XCTAssertFalse(app.tabBars.buttons["小重点"].exists)
        shot("01-首页")
        app.tabBars.buttons["课程"].tap()
        app.buttons["book-7u"].tap()
        app.buttons["lesson-7u-02"].tap()
        XCTAssertTrue(app.buttons["refresh-lesson"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["refresh-lesson"].label, "联网查找本课资料")
        shot("02-济南的冬天资料")
        XCTAssertFalse(app.buttons["B站试讲 ↗"].exists)
        openOutlineCategory(app)
        let guide = app.buttons["resource-curated-guide-7u-02"]
        XCTAssertTrue(guide.waitForExistence(timeout: 5)); guide.tap()
        XCTAssertTrue(app.buttons["study-note"].waitForExistence(timeout: 5))
        shot("03-学习页面")
        app.buttons["study-note"].tap()
        let note = app.textViews["note-input"]; XCTAssertTrue(note.waitForExistence(timeout: 4))
        note.tap(); note.typeText("test winter focus")
        app.buttons["save-note"].tap()
        app.tabBars.buttons["课表"].tap()
        XCTAssertTrue(app.buttons["星期四"].waitForExistence(timeout: 5)); app.buttons["星期四"].tap()
        XCTAssertTrue(app.staticTexts["休息15分钟"].firstMatch.waitForExistence(timeout: 4))
        shot("04-中文课表")
        app.tabBars.buttons["我的"].tap()
        app.buttons["上课提醒"].tap()
        XCTAssertTrue(app.staticTexts["1 · 设置接收手机"].waitForExistence(timeout: 4))
        shot("05-Bark设置")
        app.terminate(); app.launch()
        app.tabBars.buttons["我的"].tap()
        app.buttons["我的笔记与收藏"].tap()
        XCTAssertTrue(app.staticTexts["test winter focus"].firstMatch.waitForExistence(timeout: 5))
        shot("06-保存的笔记")
    }
    func testSearchSelectsLessonThenResourceAndPDFHighlightsPersist() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["课程"].tap()
        XCTAssertTrue(app.staticTexts["local-search-hint"].exists)
        XCTAssertTrue(app.staticTexts["local-search-hint"].label.contains("本机"))
        XCTAssertTrue(app.staticTexts["local-search-hint"].label.contains("联网查找"))
        let search = app.textFields["search-input"]; search.tap(); search.typeText("老舍\n")
        XCTAssertTrue(app.staticTexts["result-count"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["search-lesson-7u-02"].waitForExistence(timeout: 4))
        app.buttons["search-lesson-7u-02"].tap()
        openOutlineCategory(app)
        app.buttons["resource-curated-guide-7u-02"].tap()
        XCTAssertTrue(app.buttons["study-note"].waitForExistence(timeout: 4))
        shot("07-课文搜索进入学习资料")
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["清空搜索"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-01"].tap()
        let resource = app.buttons["resource-ui-pdf"]
        for _ in 0..<6 { if resource.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(resource.isHittable); resource.tap()
        app.buttons["选择本页文字"].tap(); app.buttons["高亮选区"].tap()
        XCTAssertTrue(app.textViews["quote-input"].waitForExistence(timeout: 4))
        app.buttons["save-note"].tap()
        XCTAssertTrue(app.staticTexts["已保存 1 处高亮"].waitForExistence(timeout: 4))
        shot("08-PDF划重点")
    }
    func testExactTitleAndAuthorSearchGroupsLessons() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["课程"].tap()
        let search = app.textFields["search-input"]
        search.tap(); search.typeText("春\n")
        let count = app.staticTexts["result-count"]
        XCTAssertTrue(count.waitForExistence(timeout: 4))
        let springCount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "找到 1 篇课文 · "), object: count)
        wait(for: [springCount], timeout: 4)
        XCTAssertTrue(app.buttons["search-lesson-7u-01"].exists)
        XCTAssertTrue(app.buttons["search-lesson-7u-01"].isHittable, "The identified result must remain an actionable lesson row")
        XCTAssertFalse(app.buttons["search-lesson-7d-extra3-4"].exists)
        app.buttons["清空搜索"].tap()
        search.tap(); search.typeText("毛泽东\n")
        let authorCount = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "找到 3 篇课文 · "), object: count)
        wait(for: [authorCount], timeout: 4)
        for id in ["7u-13", "8u-01", "9u-01"] {
            XCTAssertTrue(app.buttons["search-lesson-" + id].waitForExistence(timeout: 4))
        }
        XCTAssertTrue(app.segmentedControls.buttons["文字资料"].exists)
    }
    private func tapNativeTransportButton(_ native: XCUIElement, expecting labelPattern: String) throws {
        let button = native.buttons["Play/Pause"] // Actual stock AVKit identifier, scoped to its controller.
        let nativeFrame = native.frame
        let initialFrame = button.exists ? (try button.snapshot()).frame : .zero
        let hasVisibleFrame = !initialFrame.isEmpty && nativeFrame.contains(initialFrame)
        if !hasVisibleFrame || !button.isHittable {
            // AX evidence: center y426 hits the existing138pt transport button (y373...511).
            // The portrait player background at68% height is below that row and above the bottom controls.
            let background = CGVector(dx: 0.5, dy: 0.68)
            let point = CGPoint(x: nativeFrame.minX + nativeFrame.width * background.dx,
                                y: nativeFrame.minY + nativeFrame.height * background.dy)
            XCTAssertFalse(initialFrame.contains(point), "Reveal must not activate the transport control")
            native.coordinate(withNormalizedOffset: background).tap()
        }
        let expectedLabel = NSPredicate(format: "SELF MATCHES[c] %@", labelPattern)
        var transportSnapshot: XCUIElementSnapshot?
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard button.exists, button.isHittable, let snapshot = try? button.snapshot(),
                  expectedLabel.evaluate(with: snapshot.label), !snapshot.frame.isEmpty,
                  nativeFrame.contains(snapshot.frame) else { return false }
            transportSnapshot = snapshot
            return true
        }, object: nil)
        wait(for: [ready], timeout: 5)
        let snapshot = try XCTUnwrap(transportSnapshot, "Stock AVKit transport must exist, be hittable and have the expected label and visible frame")
        let buttonFrame = snapshot.frame
        XCTAssertTrue(expectedLabel.evaluate(with: snapshot.label), "Stock AVKit transport must have the expected playback state")
        XCTAssertFalse(buttonFrame.isEmpty, "Stock AVKit transport control must have a visible frame")
        XCTAssertTrue(nativeFrame.contains(buttonFrame), "Stock AVKit transport control must be inside its native player")
        // Read label and geometry from the same snapshot; no transient-child queries between readiness and the gesture.
        native.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(
            CGVector(dx: buttonFrame.midX - nativeFrame.minX, dy: buttonFrame.midY - nativeFrame.minY)).tap()
    }
    private func openOutlineCategory(_ app: XCUIApplication) {
        let category = app.buttons["备课提纲"].firstMatch
        // Scroll the actual horizontal picker before asking about its clipped offscreen last item.
        // XCTest may fail the test while computing isHittable for a wholly clipped button.
        let picker = app.scrollViews["lesson-category-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.swipeLeft()
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertTrue(category.isHittable)
        category.tap()
    }
    // This lesson's actual decoded image is 1280x720. AVKit uses aspect-fit in both containers.
    // Sample only its inset image, never letterboxing, app chrome or accessible transport overlays.
    @discardableResult private func assertRenderedVideo(_ app: XCUIApplication, playerID: String, phase: String,
                                                       enforceImageGate: Bool = true, sameItemCapture: Bool = false) throws -> Bool {
        let player = app.descendants(matching: .any)[playerID].firstMatch
        XCTAssertTrue(player.waitForExistence(timeout: 5), phase)
        if playerID == "fullscreen-native-player" {
            let status = player.descendants(matching: .any)["fullscreen-video-render-status"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout: 5), phase)
            wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "画面已就绪 · 已暂停"), object: status)], timeout: 16)
        }
        var decodedReceipt = "output-disabled"
        if sameItemCapture {
            let capture = app.buttons["same-item-render-capture"]
            XCTAssertTrue(capture.waitForExistence(timeout: 5))
            XCTAssertTrue(capture.isHittable)
            let priorReceipt = capture.value as? String
            capture.tap() // Exactly one request; a missing/new-buffer miss remains honest evidence.
            decodedReceipt = try XCTUnwrap(capture.value as? String)
            XCTAssertNotEqual(decodedReceipt, "0", "A capture request must have a numeric receipt")
            XCTAssertNotEqual(decodedReceipt, priorReceipt, "A stale receipt cannot pair a later screenshot")
        }
        // A single AX snapshot supplies player geometry and all masks before the screenshot.
        func flattened(_ node: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
            [node] + node.children.flatMap { flattened($0) }
        }
        let before = try app.snapshot()
        let nodes = flattened(before)
        let native = try XCTUnwrap(nodes.first { $0.identifier == playerID }, phase)
        let frame = native.frame, bounds = before.frame
        if playerID == "fullscreen-native-player" {
            XCTAssertEqual(nodes.first { $0.identifier == "fullscreen-video-render-status" }?.value as? String,
                           "画面已就绪 · 已暂停", phase)
        }
        let overlays = nodes.filter { [XCUIElement.ElementType.button, .slider, .staticText].contains($0.elementType) }
            .map { $0.frame.insetBy(dx: -4, dy: -4) }
        let screenStartUptime = ProcessInfo.processInfo.systemUptime
        let screenshot = XCUIScreen.main.screenshot()
        let screenEndUptime = ProcessInfo.processInfo.systemUptime
        let full = XCTAttachment(screenshot: screenshot)
        full.name = "rendered-video-raw-" + phase; full.lifetime = .keepAlways; add(full)
        let raw = screenshot.image
        let image = try uprightVideoImage(raw)
        let source = try XCTUnwrap(image.cgImage, phase)
        let width = min(frame.width, frame.height * 16 / 9)
        let height = width * 9 / 16
        let video = CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
        let region = video.insetBy(dx: width * 0.10, dy: height * 0.10)
        let scaleX = CGFloat(source.width) / bounds.width
        let scaleY = CGFloat(source.height) / bounds.height
        let pixels = videoPixelRect(region, bounds: bounds, image: source)
        let diagnostic = XCTAttachment(string: """
        phase=\(phase) deviceOrientation=\(XCUIDevice.shared.orientation.rawValue)
        rawUIImageOrientation=\(raw.imageOrientation.rawValue) rawUIImageSize=\(raw.size) rawScale=\(raw.scale)
        rawCGImage=\(raw.cgImage?.width ?? -1)x\(raw.cgImage?.height ?? -1)
        uprightCGImage=\(source.width)x\(source.height) appFrame=\(bounds) playerFrame=\(frame)
        renderStatus=\(nodes.first { $0.identifier == "fullscreen-video-render-status" }?.value ?? "inline") video=\(video) regionAX=\(region) regionPixels=\(pixels)
        scaleX=\(scaleX) scaleY=\(scaleY) masksAX=\(overlays)
        screenshotStartUptime=\(screenStartUptime) screenshotEndUptime=\(screenEndUptime)
        decodedReceipt=\(decodedReceipt)
        """)
        diagnostic.name = "rendered-video-coordinates-" + phase; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(frame.width.isFinite && frame.height.isFinite && frame.width > 0 && frame.height > 0, phase)
        XCTAssertEqual(bounds.origin, .zero, phase + ": main-screen screenshot requires a fullscreen app")
        XCTAssertEqual(scaleX / scaleY, 1, accuracy: 0.01, phase + ": upright screenshot axes must match AX screen axes")
        XCTAssertTrue(bounds.contains(region) && !region.isEmpty, phase + ": video crop must be on screen")
        XCTAssertTrue(CGRect(x: 0, y: 0, width: source.width, height: source.height).contains(pixels), phase)
        let after = try app.snapshot()
        let afterNodes = flattened(after)
        XCTAssertEqual(after.frame, bounds, phase + ": screen geometry changed during capture")
        let afterNative = try XCTUnwrap(afterNodes.first { $0.identifier == playerID }, phase)
        XCTAssertEqual(afterNative.frame, frame, phase + ": player moved during capture")
        XCTAssertEqual(afterNative.value as? String, native.value as? String, phase + ": player state changed during capture")
        if playerID == "fullscreen-native-player" {
            XCTAssertEqual(afterNodes.first { $0.identifier == "fullscreen-video-render-status" }?.value as? String,
                           "画面已就绪 · 已暂停", phase + ": restoration/presentation changed during capture")
        }
        XCTAssertEqual(afterNodes.filter { [XCUIElement.ElementType.button, .slider, .staticText].contains($0.elementType) }
            .map { $0.frame.insetBy(dx: -4, dy: -4) }, overlays, phase + ": overlay geometry changed during capture")
        let crop = try XCTUnwrap(source.cropping(to: pixels), phase)
        let cropped = XCTAttachment(image: UIImage(cgImage: crop))
        cropped.name = "rendered-video-region-" + phase; cropped.lifetime = .keepAlways; add(cropped)
        let sampleWidth = 64, sampleHeight = 36, bytesPerRow = sampleWidth * 4
        let rgba = try videoRGBA(crop, width: sampleWidth, height: sampleHeight)
        var colors: [Int: Int] = [:]
        var samples = 0
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let point = videoSamplePoint(x: x, y: y, width: sampleWidth, height: sampleHeight,
                                             pixels: pixels, bounds: bounds, image: source)
                if overlays.contains(where: { $0.contains(point) }) { continue }
                let offset = y * bytesPerRow + x * 4
                // Explicit RGBA context owns exactly width * height * 4 bytes.
                let color = (Int(rgba[offset]) >> 4) << 8 | (Int(rgba[offset + 1]) >> 4) << 4 | (Int(rgba[offset + 2]) >> 4)
                colors[color, default: 0] += 1; samples += 1
            }
        }
        XCTAssertGreaterThan(samples, sampleWidth * sampleHeight / 4, phase + ": overlays obscure the video sample")
        let populatedColors = colors.values.filter { $0 >= 4 }.count
        let informative = populatedColors >= 16 && (colors.values.max() ?? samples) < samples * 9 / 10
        let statistics = XCTAttachment(string: "samples=\(samples) populatedColors=\(populatedColors) largestBucket=\(colors.values.max() ?? 0) bufferBytes=\(rgba.count) informative=\(informative) enforceImageGate=\(enforceImageGate)")
        statistics.name = "rendered-video-statistics-" + phase; statistics.lifetime = .keepAlways; add(statistics)
        if enforceImageGate {
            XCTAssertGreaterThanOrEqual(populatedColors, 16, phase + ": rendered lesson must vary; uniform green/black is a failure (colors=\(populatedColors), samples=\(samples))")
            XCTAssertLessThan(colors.values.max() ?? samples, samples * 9 / 10, phase + ": nearly uniform rendered video")
        }
        return informative
    }
    // UIImage.draw applies EXIF/UIImage orientation, including mirroring. The output owns upright pixels.
    private func uprightVideoImage(_ image: UIImage) throws -> UIImage {
        let raw = try XCTUnwrap(image.cgImage)
        let swapsAxes = [UIImage.Orientation.left, .right, .leftMirrored, .rightMirrored].contains(image.imageOrientation)
        let size = CGSize(width: swapsAxes ? raw.height : raw.width, height: swapsAxes ? raw.width : raw.height)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    private func videoPixelRect(_ region: CGRect, bounds: CGRect, image: CGImage) -> CGRect {
        let sx = CGFloat(image.width) / bounds.width, sy = CGFloat(image.height) / bounds.height
        let left = ceil((region.minX - bounds.minX) * sx), top = ceil((region.minY - bounds.minY) * sy)
        return CGRect(x: left, y: top, width: floor((region.maxX - bounds.minX) * sx) - left,
                      height: floor((region.maxY - bounds.minY) * sy) - top)
    }
    private func videoSamplePoint(x: Int, y: Int, width: Int, height: Int,
                                  pixels: CGRect, bounds: CGRect, image: CGImage) -> CGPoint {
        CGPoint(x: bounds.minX + (pixels.minX + (CGFloat(x) + 0.5) * pixels.width / CGFloat(width)) * bounds.width / CGFloat(image.width),
                y: bounds.minY + (pixels.minY + (CGFloat(y) + 0.5) * pixels.height / CGFloat(height)) * bounds.height / CGFloat(image.height))
    }
    private func videoRGBA(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = rgba.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .none
            // CGImage raster row order is retained; the synthetic color-label check below verifies it.
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(rendered)
        return rgba
    }
    // Executed at the start of the real playback test, even when CI selects only that method.
    // This labeled fixture verifies coordinate machinery only; it never supplies video acceptance pixels.
    private func checkRenderedVideoImageCoordinates() throws {
        let colors: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255]]
        var bytes: [UInt8] = []
        for y in 0..<12 { for x in 0..<8 { bytes += colors[(y < 6 ? 0 : 2) + (x < 4 ? 0 : 1)] } }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let raw = try XCTUnwrap(CGImage(width: 8, height: 12, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 32,
                                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        // Independently specified display corner labels: TL, TR, BL, BR for UIImage's EXIF orientations.
        let cases: [(UIImage.Orientation, [Int])] = [(.up, [0, 1, 2, 3]), (.left, [1, 3, 0, 2]),
            (.right, [2, 0, 3, 1]), (.down, [3, 2, 1, 0]), (.upMirrored, [1, 0, 3, 2]),
            (.downMirrored, [2, 3, 0, 1]), (.leftMirrored, [0, 2, 1, 3]), (.rightMirrored, [3, 1, 2, 0])]
        for (orientation, expected) in cases {
            let normalized = try uprightVideoImage(UIImage(cgImage: raw, scale: 1, orientation: orientation))
            let image = try XCTUnwrap(normalized.cgImage)
            XCTAssertEqual(normalized.imageOrientation, .up)
            let rotated = [UIImage.Orientation.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
            XCTAssertEqual(image.width, rotated ? 12 : 8); XCTAssertEqual(image.height, rotated ? 8 : 12)
            let rgba = try videoRGBA(image, width: 8, height: 8)
            for (corner, pixel) in [(0, 2 * 8 + 2), (1, 2 * 8 + 6), (2, 6 * 8 + 2), (3, 6 * 8 + 6)] {
                XCTAssertEqual(Array(rgba[(pixel * 4)..<(pixel * 4 + 4)]), colors[expected[corner]], "orientation \(orientation.rawValue), corner \(corner)")
            }
            // A nonzero AX origin and explicit top-left quadrant establish crop AND mask alignment.
            let bounds = CGRect(x: 10, y: 20, width: image.width * 10, height: image.height * 10)
            let mask = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width / 2, height: bounds.height / 2)
            let crop = try XCTUnwrap(image.cropping(to: videoPixelRect(mask, bounds: bounds, image: image)))
            XCTAssertEqual(Array(try videoRGBA(crop, width: 1, height: 1).prefix(4)), colors[expected[0]], "top-left crop \(orientation.rawValue)")
            var masked: [Int] = []
            let allPixels = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            for y in 0..<8 { for x in 0..<8 {
                if mask.contains(videoSamplePoint(x: x, y: y, width: 8, height: 8, pixels: allPixels, bounds: bounds, image: image)) {
                    masked.append(y * 8 + x)
                }
            } }
            XCTAssertEqual(masked, [0, 1, 2, 3, 8, 9, 10, 11, 16, 17, 18, 19, 24, 25, 26, 27], "top-left mask \(orientation.rawValue)")
        }
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func videoSeconds(_ label: String) -> Int? {
        let parts = label.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 || parts.count == 3 else { return nil }
        return parts.reduce(0) { $0 * 60 + $1 }
    }
}
