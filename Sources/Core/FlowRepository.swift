import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// Private local SQLite store; all access serialized by an actor.
public actor FlowRepository {
    private var db: OpaquePointer?
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw StoreError.open }
        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS clips(id TEXT PRIMARY KEY, body TEXT NOT NULL, created REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0); CREATE INDEX IF NOT EXISTS clips_order ON clips(pinned DESC, created DESC);", nil, nil, nil) == SQLITE_OK else { throw StoreError.query }
    }
    deinit { if let db { sqlite3_close(db) } }
    public enum StoreError: Error { case open, query }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw StoreError.query }
        return s
    }
    public func save(_ clip: Clip) throws {
        let s = try statement("INSERT OR REPLACE INTO clips(id,body,created,pinned) VALUES(?,?,?,?)")
        defer { sqlite3_finalize(s) }
        _ = clip.id.uuidString.withCString { sqlite3_bind_text(s, 1, $0, -1, unsafeBitCastDestructor) }
        _ = clip.text.withCString { sqlite3_bind_text(s, 2, $0, -1, unsafeBitCastDestructor) }
        sqlite3_bind_double(s, 3, clip.createdAt.timeIntervalSince1970)
        sqlite3_bind_int(s, 4, clip.pinned ? 1 : 0)
        guard sqlite3_step(s) == SQLITE_DONE else { throw StoreError.query }
    }
    public func delete(id: UUID) throws {
        let s = try statement("DELETE FROM clips WHERE id=?")
        defer { sqlite3_finalize(s) }
        _ = id.uuidString.withCString { sqlite3_bind_text(s, 1, $0, -1, unsafeBitCastDestructor) }
        guard sqlite3_step(s) == SQLITE_DONE else { throw StoreError.query }
    }
    public func list(search: String = "", limit: Int = 500) throws -> [Clip] {
        // LIKE is parameterized and escaped, so pasted '%' / '_' aren't wildcard searches.
        let s = try statement("SELECT id,body,created,pinned FROM clips WHERE body LIKE ? ESCAPE '\\' ORDER BY pinned DESC,created DESC LIMIT ?")
        defer { sqlite3_finalize(s) }
        let escaped = search.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_")
        _ = ("%" + escaped + "%").withCString { sqlite3_bind_text(s, 1, $0, -1, unsafeBitCastDestructor) }
        sqlite3_bind_int(s, 2, Int32(max(1, min(limit, 1000))))
        var output: [Clip] = []
        while sqlite3_step(s) == SQLITE_ROW {
            guard let i = sqlite3_column_text(s, 0), let b = sqlite3_column_text(s, 1), let id = UUID(uuidString: String(cString: i)) else { continue }
            output.append(Clip(id: id, text: String(cString: b), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(s, 2)), pinned: sqlite3_column_int(s, 3) != 0))
        }
        return output
    }
    public func exportJSON() throws -> Data {
        try JSONEncoder().encode(list(limit: 1000))
    }
}

// SQLITE_TRANSIENT: sqlite must own the UTF-8 text after temporary Swift buffers disappear.
private let unsafeBitCastDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
