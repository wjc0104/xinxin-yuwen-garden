import XCTest

final class GardenUITests: XCTestCase {
    func testCatalogNotesAndAllTabs() throws {
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
        app.tabBars.buttons["找资料"].tap(); shot("03-找资料")
        app.tabBars.buttons["小重点"].tap()
        XCTAssertTrue(app.staticTexts["test focus"].firstMatch.waitForExistence(timeout: 4))
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
