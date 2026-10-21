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
        let play = app.buttons["video-play-pause"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: play)
        wait(for: [ready], timeout: 40)
        play.tap()
        let position = app.staticTexts["video-position"]
        let moving = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@ AND label != %@ AND label != %@", "--:--", "00:00", ""), object: position)
        wait(for: [moving], timeout: 25)
        shot("09-视频学习与笔记")
        app.buttons["边看边记"].tap()
        let note = app.textViews["video-note-input"]; XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap(); note.typeText("test video timestamp")
        let time = app.textFields["分:秒 或 时:分:秒"]
        XCTAssertNotEqual(time.value as? String, "", "The note must capture the native player's real time")
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
        shot("13-视频与内联笔记草稿")
        app.buttons["video-save-note"].tap()
        XCTAssertTrue(app.staticTexts["03:25"].firstMatch.waitForExistence(timeout: 5))
        shot("10-视频时间笔记")
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
        if !category.isHittable {
            let start = app.buttons["试讲稿"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            let end = app.buttons["全部"].firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(category.isHittable)
        category.tap()
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
