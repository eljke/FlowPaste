import XCTest
@testable import FlowPasteCore

final class FlowIncomingTests: XCTestCase {
    func testWebLink() throws {
        let value = "https://example.org/путь?token=a%2Fb+z&utm_source=safari#part"
        let url = try XCTUnwrap(URL(string: value))
        XCTAssertEqual(try FlowIncoming(url: url), .text(url.absoluteString))
        XCTAssertEqual(try FlowIncoming(url: XCTUnwrap(URL(string: "http://example.org"))), .text("http://example.org"))
    }

    func testFileRoute() throws {
        let url = URL(fileURLWithPath: "/tmp/shared text.json")
        XCTAssertEqual(try FlowIncoming(url: url), .file(url))
    }

    func testTextFile() throws {
        let text = "Привет 👋\r\n{\"n\":12345678901234567890}"
        XCTAssertEqual(try FlowIncoming.decodeFile(Data(text.utf8)), text)
        XCTAssertEqual(try FlowIncoming.decodeFile(Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8)), text)
    }

    func testImportLink() throws {
        let text = "Привет + & % # 👋\nhttps://example.org/?token=a%2Fb"
        var components = try XCTUnwrap(URLComponents(string: "flowpaste://import"))
        components.queryItems = [URLQueryItem(name: "text", value: text)]
        XCTAssertEqual(try FlowIncoming(url: XCTUnwrap(components.url)), .text(text))
        for value in ["flowpaste://import", "flowpaste://import?text=", "flowpaste://other?text=x", "flowpaste://import?text=x&text=y", "flowpaste://import?text=x#ignored"] {
            XCTAssertThrowsError(try FlowIncoming(url: XCTUnwrap(URL(string: value))))
        }
    }

    func testInvalidInput() throws {
        XCTAssertThrowsError(try FlowIncoming(url: XCTUnwrap(URL(string: "relative/path"))))
        XCTAssertThrowsError(try FlowIncoming.decodeFile(Data([0xFF, 0x00])))
        XCTAssertThrowsError(try FlowIncoming.decodeFile(Data()))
        XCTAssertThrowsError(try FlowIncoming.decodeFile(Data(repeating: 65, count: FlowEngine.maximumTextBytes + 1)))
    }
}
