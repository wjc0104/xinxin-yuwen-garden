import XCTest

final class GardenUITests: XCTestCase {
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
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5))
        shot("02-济南的冬天资料")
        XCTAssertFalse(app.buttons["B站试讲 ↗"].exists)
        app.segmentedControls.buttons["教案与试讲"].tap()
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
    func testSearchReturnsResourcesAndPDFHighlightsPersist() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.tabBars.buttons["课程"].tap()
        let search = app.textFields["search-input"]; search.tap(); search.typeText("老舍")
        XCTAssertTrue(app.staticTexts["result-count"].waitForExistence(timeout: 4))
        shot("07-实际资料搜索")
        app.buttons["清空搜索"].tap()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-01"].tap()
        app.segmentedControls.buttons["教案与试讲"].tap()
        let resource = app.buttons["resource-ui-pdf"]
        for _ in 0..<6 { if resource.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(resource.isHittable); resource.tap()
        app.buttons["选择本页文字"].tap(); app.buttons["高亮选区"].tap()
        XCTAssertTrue(app.textViews["quote-input"].waitForExistence(timeout: 4))
        app.buttons["save-note"].tap()
        XCTAssertTrue(app.staticTexts["已保存 1 处高亮"].waitForExistence(timeout: 4))
        shot("08-PDF划重点")
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
