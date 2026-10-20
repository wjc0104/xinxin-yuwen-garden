import XCTest

final class GardenUITests: XCTestCase {
    func testPDFSelectionHighlightSurvivesRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--ui-testing"]; app.launch()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-01"].tap()
        let resource = app.buttons["resource-ui-pdf"]
        if !resource.isHittable { app.swipeUp() }
        XCTAssertTrue(resource.waitForExistence(timeout: 4)); resource.tap()
        app.buttons["选择本页文字"].tap()
        app.buttons["高亮选区"].tap()
        XCTAssertTrue(app.textViews["quote-input"].waitForExistence(timeout: 4))
        XCTAssertTrue((app.textViews["quote-input"].value as? String ?? "").contains("PDF Garden Focus"))
        app.buttons["save-note"].tap()
        XCTAssertTrue(app.staticTexts["已保存 1 处高亮"].waitForExistence(timeout: 4))
        shot("07-PDF高亮")
        app.terminate(); app.launch()
        app.buttons["book-7u"].tap(); app.buttons["lesson-7u-01"].tap()
        if !app.buttons["resource-ui-pdf"].isHittable { app.swipeUp() }
        app.buttons["resource-ui-pdf"].tap()
        XCTAssertTrue(app.staticTexts["已保存 1 处高亮"].waitForExistence(timeout: 4))
    }
    func testCatalogNotesAndAllTabs() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.buttons["book-7u"].waitForExistence(timeout: 15))
        shot("01-小花园目录")
        app.buttons["book-7u"].tap()
        app.buttons["lesson-7u-01"].tap()
        XCTAssertTrue(app.staticTexts["春"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["new-note"].tap()
        let note = app.textViews["note-input"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.tap(); note.typeText("test focus")
        app.buttons["save-note"].tap()
        XCTAssertTrue(app.staticTexts["test focus"].firstMatch.waitForExistence(timeout: 4))
        shot("02-课文与重点")
        app.tabBars.buttons["找资料"].tap()
        XCTAssertTrue(app.textFields["search-input"].waitForExistence(timeout: 5))
        shot("03-找资料")
        app.tabBars.buttons["小重点"].tap()
        XCTAssertTrue(app.staticTexts["test focus"].firstMatch.waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["回到课文"].firstMatch.waitForExistence(timeout: 4))
        shot("04-小重点")
        app.tabBars.buttons["课表"].tap()
        XCTAssertTrue(app.staticTexts["上课的小约定"].waitForExistence(timeout: 4))
        shot("05-课表")
        app.tabBars.buttons["我的"].tap()
        XCTAssertTrue(app.staticTexts["权限由你决定"].waitForExistence(timeout: 4))
        shot("06-我的")
        app.terminate(); app.launch()
        app.tabBars.buttons["小重点"].tap()
        XCTAssertTrue(app.staticTexts["test focus"].firstMatch.waitForExistence(timeout: 4), "Notes survive relaunch")
    }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
