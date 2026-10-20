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

    func testInvalidInput() throws {
        XCTAssertThrowsError(try FlowIncoming(url: XCTUnwrap(URL(string: "relative/path"))))
        XCTAssertThrowsError(try FlowIncoming.decodeFile(Data([0xFF, 0x00])))
        XCTAssertThrowsError(try FlowIncoming.decodeFile(Data()))
        XCTAssertThrowsError(try FlowIncoming.decodeFile(Data(repeating: 65, count: FlowEngine.maximumTextBytes + 1)))
    }
}
