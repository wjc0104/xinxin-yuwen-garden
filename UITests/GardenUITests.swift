import XCTest

final class GardenUITests: XCTestCase {
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
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
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
        play.tap()
        let position = app.staticTexts["video-position"]
        let moving = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label != %@ AND label != %@", "--:--", "00:00", ""), object: position)
        wait(for: [moving], timeout: 25)
        XCTAssertEqual(speed.label, "倍速 1.5×")
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
        app.buttons["video-fullscreen"].tap()
        let exit = app.buttons["video-exit-fullscreen"]
        XCTAssertTrue(exit.waitForExistence(timeout: 5))
        let fullscreenSpeed = app.buttons["fullscreen-video-speed"]
        XCTAssertEqual(fullscreenSpeed.label, "倍速 1.5×")
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
        shot("15-原生视频横屏全屏")
        XCUIDevice.shared.orientation = .landscapeRight
        wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "landscapeLeft"), object: orientation)], timeout: 8)
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        let secondNativeFrame = app.descendants(matching: .any)["fullscreen-native-player"].firstMatch.frame
        XCTAssertGreaterThan(secondNativeFrame.width, secondNativeFrame.height)
        XCTAssertGreaterThan(secondNativeFrame.width, app.frame.width * 0.9)
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
