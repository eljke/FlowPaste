import XCTest
@testable import FlowPasteCore
final class FlowTests: XCTestCase {
    func testURL() throws {
        XCTAssertEqual(try FlowEngine.apply(.cleanLink, to: "https://example.org/a?utm_source=x&id=42&fbclid=abc"), "https://example.org/a?id=42")
        XCTAssertEqual(try FlowEngine.apply(.cleanLink, to: "https://example.org/a?token=secret"), "https://example.org/a?token=secret")
    }
    func testText() throws {
        XCTAssertEqual(try FlowEngine.apply(.deduplicateLines, to: "a\nb\na"), "a\nb")
        XCTAssertEqual(try FlowEngine.apply(.trimSpaces, to: "  one    two  "), "one two")
        XCTAssertEqual(try FlowEngine.apply(.decodeBase64, to: "0J/RgNC40LLQtdGC"), "Привет")
    }
    func testJSON() throws {
        XCTAssertTrue(try FlowEngine.apply(.prettyJSON, to: "{\"z\":3,\"a\":1}").contains("\n"))
        XCTAssertThrowsError(try FlowEngine.apply(.prettyJSON, to: "hello"))
    }
    func testDatabase() async throws {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("flow.sqlite")
        let repo = try FlowRepository(url: u)
        let a = Clip(text: "Привет, Мир")
        try await repo.save(a)
        let n0 = try await awaitCount(repo, "Привет")
        XCTAssertEqual(n0, 1)
        let n1 = try await awaitCount(repo, "%")
        XCTAssertEqual(n1, 0)
        try await repo.save(Clip(id: a.id, text: a.text, createdAt: a.createdAt, pinned: true))
        let n2 = try await awaitCount(repo, "Мир")
        XCTAssertEqual(n2, 1)
        try await repo.delete(id: a.id)
        let n3 = try await awaitCount(repo, "")
        XCTAssertEqual(n3, 0)
    }
    private func awaitCount(_ repo: FlowRepository, _ search: String) async throws -> Int { try await repo.list(search: search).count }
}
