import XCTest

final class FlowWorkflowTests: XCTestCase {
    func testIncomingLink() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        let first = try XCTUnwrap(URL(string: "https://example.org/shared?utm_source=safari&id=7#part"))
        app.open(first)
        let editor = app.textViews.firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, first.absoluteString)
        tap(app.buttons["Очистить ссылку"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["https://example.org/shared?id=7#part"].waitForExistence(timeout: 5))

        let second = try XCTUnwrap(URL(string: "http://example.org/another?x=a%2Bb%26c"))
        app.tabBars.buttons["История"].tap()
        app.open(second)
        XCTAssertTrue(app.alerts["Открыть полученный текст?"].waitForExistence(timeout: 5))
        app.buttons["Отмена"].tap()
        XCTAssertEqual(editor.value as? String, first.absoluteString)
        app.open(second)
        XCTAssertTrue(app.alerts["Открыть полученный текст?"].waitForExistence(timeout: 5))
        app.buttons["Заменить текст"].tap()
        XCTAssertEqual(editor.value as? String, second.absoluteString)
        XCTAssertFalse(app.staticTexts["Результат"].exists)

        app.open(second)
        XCTAssertFalse(app.alerts["Открыть полученный текст?"].exists)
        XCTAssertEqual(editor.value as? String, second.absoluteString)
        app.terminate()
    }

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
        let record = app.buttons[result].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5), app.debugDescription)
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
