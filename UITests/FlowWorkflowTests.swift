import XCTest

final class FlowWorkflowTests: XCTestCase {
    func testTextHistoryAndUndo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        tap(app.buttons["Попробовать на примере"], in: app)
        let clean = app.buttons["Очистить ссылку"].firstMatch
        XCTAssertTrue(clean.waitForExistence(timeout: 5))
        tap(clean, in: app)
        let result = "https://example.org/article?id=42#read"
        XCTAssertTrue(app.staticTexts[result].firstMatch.waitForExistence(timeout: 5))
        tap(app.buttons["В историю"], in: app)
        XCTAssertTrue(app.staticTexts["Добавлено в историю"].waitForExistence(timeout: 5))
        app.tabBars.buttons["История"].tap()
        let record = app.staticTexts[result].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.tap()
        XCTAssertTrue(app.navigationBars["Запись"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "History record"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        tap(app.buttons["Открыть в инструментах"], in: app)
        app.buttons["Открыть запись"].tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews.firstMatch.value as? String, result)
        XCTAssertFalse(app.staticTexts["Результат"].exists)
        app.tabBars.buttons["История"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        record.swipeLeft()
        app.buttons["Удалить"].tap()
        XCTAssertTrue(app.buttons["Отменить"].waitForExistence(timeout: 5))
        app.buttons["Отменить"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        app.tabBars.buttons["История"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.isHittable { element.tap(); return }
            app.swipeUp()
        }
        XCTFail("Control is not reachable: \(element.label)")
    }
}
