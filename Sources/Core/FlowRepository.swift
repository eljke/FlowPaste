import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// Private local SQLite store; all access serialized by an actor.
public actor FlowRepository {
    private let db: OpaquePointer

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        let status = sqlite3_open(url.path, &connection)
        guard status == SQLITE_OK, let connection else {
            if let connection { sqlite3_close(connection) }
            throw StoreError.open
        }
        guard sqlite3_exec(connection, "PRAGMA journal_mode=WAL; CREATE TABLE IF NOT EXISTS clips(id TEXT PRIMARY KEY, body TEXT NOT NULL, created REAL NOT NULL, pinned INTEGER NOT NULL DEFAULT 0); CREATE INDEX IF NOT EXISTS clips_order ON clips(pinned DESC, created DESC);", nil, nil, nil) == SQLITE_OK else {
            sqlite3_close(connection)
            throw StoreError.query
        }
        db = connection
    }

    deinit { sqlite3_close(db) }

    public enum StoreError: LocalizedError {
        case open, query, invalidRecord
        public var errorDescription: String? {
            switch self {
            case .open: return "Не удалось открыть локальное хранилище"
            case .query: return "Не удалось выполнить операцию с историей"
            case .invalidRecord: return "Запись истории повреждена"
            }
        }
    }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var prepared: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else { throw StoreError.query }
        return prepared
    }

    public func save(_ clip: Clip) throws {
        try FlowBackup.validate(clip)
        try insert(clip, preservingExisting: false)
    }

    private func insert(_ clip: Clip, preservingExisting: Bool) throws {
        let sql = preservingExisting
            ? "INSERT INTO clips(id,body,created,pinned) VALUES(?,?,?,?) ON CONFLICT(id) DO NOTHING"
            : "INSERT INTO clips(id,body,created,pinned) VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body,created=excluded.created,pinned=excluded.pinned"
        let prepared = try statement(sql)
        defer { sqlite3_finalize(prepared) }
        try bind(clip.id.uuidString, to: prepared, at: 1)
        try bind(clip.text, to: prepared, at: 2)
        guard sqlite3_bind_double(prepared, 3, clip.createdAt.timeIntervalSince1970) == SQLITE_OK,
              sqlite3_bind_int(prepared, 4, clip.pinned ? 1 : 0) == SQLITE_OK,
              sqlite3_step(prepared) == SQLITE_DONE else { throw StoreError.query }
    }

    private func bind(_ value: String, to prepared: OpaquePointer, at index: Int32) throws {
        let status = value.utf8CString.withUnsafeBufferPointer {
            sqlite3_bind_text(prepared, index, $0.baseAddress, Int32($0.count - 1), transientDestructor)
        }
        guard status == SQLITE_OK else { throw StoreError.query }
    }

    public func delete(id: UUID) throws {
        let prepared = try statement("DELETE FROM clips WHERE id=?")
        defer { sqlite3_finalize(prepared) }
        try bind(id.uuidString, to: prepared, at: 1)
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw StoreError.query }
    }

    public func togglePin(id: UUID) throws {
        let prepared = try statement("UPDATE clips SET pinned=1-pinned WHERE id=?")
        defer { sqlite3_finalize(prepared) }
        try bind(id.uuidString, to: prepared, at: 1)
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw StoreError.query }
    }

    public func list(search: String = "", limit: Int = 500) throws -> [Clip] {
        try read(search: search, limit: max(1, min(limit, 1000)))
    }

    private func read(search: String = "", limit: Int? = nil, maximumBytes: Int? = nil) throws -> [Clip] {
        let prepared = try statement("SELECT id,body,created,pinned FROM clips ORDER BY pinned DESC,created DESC,id")
        defer { sqlite3_finalize(prepared) }
        var output: [Clip] = []
        var totalBytes = 0
        while true {
            let status = sqlite3_step(prepared)
            if status == SQLITE_DONE { return output }
            guard status == SQLITE_ROW else { throw StoreError.query }
            guard let rawID = sqlite3_column_text(prepared, 0),
                  let body = sqlite3_column_text(prepared, 1),
                  let id = UUID(uuidString: String(cString: rawID)) else { throw StoreError.invalidRecord }
            let count = Int(sqlite3_column_bytes(prepared, 1))
            totalBytes += count
            if let maximumBytes, totalBytes > maximumBytes { throw FlowBackup.BackupError.tooLarge }
            let text = String(decoding: UnsafeBufferPointer(start: body, count: count), as: UTF8.self)
            // SQLite's built-in LIKE only folds ASCII; Foundation also handles Cyrillic.
            if search.isEmpty || text.range(of: search, options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "ru_RU")) != nil {
                output.append(Clip(id: id, text: text, createdAt: Date(timeIntervalSince1970: sqlite3_column_double(prepared, 2)), pinned: sqlite3_column_int(prepared, 3) != 0))
                if let limit, output.count == limit { return output }
            }
        }
    }

    public func count() throws -> Int {
        let prepared = try statement("SELECT COUNT(*) FROM clips")
        defer { sqlite3_finalize(prepared) }
        guard sqlite3_step(prepared) == SQLITE_ROW else { throw StoreError.query }
        return Int(sqlite3_column_int64(prepared, 0))
    }

    public func exportJSON() throws -> Data {
        guard try count() <= FlowBackup.maximumClips else { throw FlowBackup.BackupError.tooLarge }
        return try FlowBackup.encode(read(maximumBytes: FlowBackup.maximumBytes))
    }

    public func restore(_ clips: [Clip]) throws -> Int {
        try FlowBackup.validate(clips)
        guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw StoreError.query }
        do {
            var inserted = 0
            for clip in clips {
                try insert(clip, preservingExisting: true)
                inserted += Int(sqlite3_changes(db))
            }
            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw StoreError.query }
            return inserted
        } catch {
            sqlite3_exec(db, "ROLLBACK", nil, nil, nil)
            throw error
        }
    }
}

// SQLITE_TRANSIENT: SQLite owns the text after temporary Swift buffers disappear.
private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
