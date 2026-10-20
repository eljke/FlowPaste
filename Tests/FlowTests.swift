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

    func testLinkEncoding() throws {
        let url = "https://example.org/a?token=a%2Fb%3D+z&UTM_source=x&tag=1&tag=2#part"
        XCTAssertEqual(try FlowEngine.apply(.cleanLink, to: url), "https://example.org/a?token=a%2Fb%3D+z&tag=1&tag=2#part")
        XCTAssertEqual(try FlowEngine.apply(.cleanLink, to: "https://example.org/?utm_source=x"), "https://example.org/")
        XCTAssertEqual(try FlowEngine.apply(.cleanLink, to: "https://example.org/?%75tm_source=x&id=1"), "https://example.org/?id=1")
        XCTAssertThrowsError(try FlowEngine.apply(.cleanLink, to: "file:///etc/passwd"))
        XCTAssertThrowsError(try FlowEngine.apply(.cleanLink, to: "https:///"))
    }

    func testWindowsLines() throws {
        XCTAssertEqual(try FlowEngine.apply(.deduplicateLines, to: "один\r\nдва\r\nодин"), "один\nдва")
        XCTAssertEqual(try FlowEngine.apply(.sortLines, to: "b\r\na"), "a\nb")
        XCTAssertEqual(try FlowEngine.apply(.trimSpaces, to: " a\tb \r\n c   d "), "a b\nc d")
    }

    func testUnicodeRoundTrip() throws {
        let text = "Привет 👨‍👩‍👧‍👦\n日本語\u{0000}конец"
        let encoded = try FlowEngine.apply(.encodeBase64, to: text)
        XCTAssertEqual(try FlowEngine.apply(.decodeBase64, to: encoded), text)
        XCTAssertThrowsError(try FlowEngine.apply(.decodeBase64, to: "/w=="))
        XCTAssertThrowsError(try FlowEngine.apply(.decodeBase64, to: "%%%"))
    }

    func testInputLimits() throws {
        XCTAssertThrowsError(try FlowEngine.apply(.prettyJSON, to: ""))
        XCTAssertThrowsError(try FlowEngine.apply(.upperCase, to: String(repeating: "я", count: FlowEngine.maximumTextBytes)))
        XCTAssertEqual(try FlowEngine.apply(.trimSpaces, to: " \t "), "")
        XCTAssertEqual(try FlowEngine.apply(.compactJSON, to: "true"), "true")
        XCTAssertEqual(FlowEngine.suggestions(for: "{\"a\":1}"), [.prettyJSON, .compactJSON])
        XCTAssertEqual(FlowEngine.suggestions(for: "https://example.org"), [.cleanLink])
        XCTAssertEqual(FlowEngine.suggestions(for: "  "), [])
    }

    func testLiteralUnicodeSearch() async throws {
        let repo = try temporaryStore()
        let clip = Clip(text: "ПРИВЕТ 100%_\\ ' OR 1=1 --\u{0000}хвост", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await repo.save(clip)
        for query in ["привет", "%_\\", "' OR 1=1 --", "хвост"] {
            let found = try await repo.list(search: query)
            XCTAssertEqual(found, [clip])
        }
        let missing = try await repo.list(search: "несуществующее")
        XCTAssertTrue(missing.isEmpty)
    }

    func testPersistenceAndPinOrder() async throws {
        let url = temporaryURL()
        let repo = try FlowRepository(url: url)
        let old = Clip(text: "Старое", createdAt: Date(timeIntervalSince1970: 10), pinned: true)
        let recent = Clip(text: "Новое", createdAt: Date(timeIntervalSince1970: 20))
        try await repo.save(recent)
        try await repo.save(old)
        let reopened = try FlowRepository(url: url)
        let found = try await reopened.list()
        XCTAssertEqual(found, [old, recent])
        try await reopened.delete(id: old.id)
        try await reopened.save(old)
        let restored = try await repo.list()
        XCTAssertEqual(restored, [old, recent])
    }

    func testCompleteBackup() async throws {
        let source = try temporaryStore()
        let clips = (0..<1005).map { Clip(text: "Запись \($0)", pinned: $0 == 0) }
        let inserted = try await source.restore(clips)
        XCTAssertEqual(inserted, clips.count)
        let data = try await source.exportJSON()
        let decoded = try FlowBackup.decode(data)
        XCTAssertEqual(Set(decoded.map(\.id)), Set(clips.map(\.id)))
        let destination = try temporaryStore()
        let restored = try await destination.restore(decoded)
        XCTAssertEqual(restored, clips.count)
        let repeated = try await destination.restore(decoded)
        XCTAssertEqual(repeated, 0)
        let count = try await destination.count()
        XCTAssertEqual(count, clips.count)
    }

    func testRestorePreservesCurrentData() async throws {
        let repo = try temporaryStore()
        let saved = Clip(text: "Текущая версия", createdAt: Date(timeIntervalSince1970: 1_700_000_000), pinned: true)
        try await repo.save(saved)
        let older = Clip(id: saved.id, text: "Старая версия", createdAt: saved.createdAt)
        let new = Clip(text: "Из копии", createdAt: Date(timeIntervalSince1970: 1_700_000_001))
        let added = try await repo.restore([older, new])
        XCTAssertEqual(added, 1)
        let found = try await repo.list()
        XCTAssertEqual(found.first, saved)
        XCTAssertTrue(found.contains(new))
    }

    func testInvalidBackupLeavesHistory() async throws {
        let repo = try temporaryStore()
        let saved = Clip(text: "Сохранено", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await repo.save(saved)
        do {
            _ = try await repo.restore([Clip(text: "Новая"), Clip(text: " \n ")])
            XCTFail("Invalid backup accepted")
        } catch {}
        let found = try await repo.list()
        XCTAssertEqual(found, [saved])
        XCTAssertThrowsError(try FlowBackup.decode(Data("{}".utf8)))
        XCTAssertThrowsError(try FlowBackup.decode(Data(repeating: 0, count: FlowBackup.maximumBytes + 1)))
        XCTAssertThrowsError(try FlowBackup.encode([saved, saved]))
        XCTAssertThrowsError(try FlowBackup.encode([Clip(text: "x", createdAt: Date(timeIntervalSince1970: .infinity))]))
    }

    func testLegacyBackup() throws {
        let clip = Clip(text: "Копия 0.1.0", pinned: true)
        XCTAssertEqual(try FlowBackup.decode(JSONEncoder().encode([clip])), [clip])
    }

    func testConcurrentSaves() async throws {
        let repo = try temporaryStore()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<50 { group.addTask { try await repo.save(Clip(text: "\(index)")) } }
            try await group.waitForAll()
        }
        let count = try await repo.count()
        XCTAssertEqual(count, 50)
    }

    func testRepeatedPinToggle() async throws {
        let repo = try temporaryStore()
        let clip = Clip(text: "Текст", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await repo.save(clip)
        try await repo.togglePin(id: clip.id)
        let pinned = try await repo.list()
        XCTAssertTrue(try XCTUnwrap(pinned.first).pinned)
        try await repo.togglePin(id: clip.id)
        let unpinned = try await repo.list()
        XCTAssertEqual(unpinned, [clip])
    }

    func testOversizedExportFails() async throws {
        let repo = try temporaryStore()
        let text = String(repeating: "a", count: FlowEngine.maximumTextBytes)
        for _ in 0..<21 { try await repo.save(Clip(text: text)) }
        do {
            _ = try await repo.exportJSON()
            XCTFail("Truncated or oversized backup exported")
        } catch FlowBackup.BackupError.tooLarge {}
        let count = try await repo.count()
        XCTAssertEqual(count, 21)
    }

    private func temporaryURL() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("clips.sqlite")
    }

    private func temporaryStore() throws -> FlowRepository { try FlowRepository(url: temporaryURL()) }
}
