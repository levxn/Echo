import Foundation
import os
import SQLite3

/// Thin SQLite wrapper: the `chunk` table plus an FTS5 index (`chunk_fts`) and an embedding BLOB per chunk.
actor ChunkStore {
    private var db: OpaquePointer?
    let chunksDirectory: URL

    /// `directory` lets tests use a temp folder; the app uses Application Support/Echo.
    init(directory: URL? = nil) {
        let base = directory ?? URL.applicationSupportDirectory.appending(path: "Echo", directoryHint: .isDirectory)
        chunksDirectory = base.appending(path: "chunks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: chunksDirectory, withIntermediateDirectories: true)
        if sqlite3_open(base.appending(path: "echo.sqlite").path, &db) != SQLITE_OK { Log.app.error("sqlite open failed") }
        Self.migrate(db)
    }

    deinit { sqlite3_close(db) }

    func url(for audioFile: String) -> URL { chunksDirectory.appending(path: audioFile) }

    // MARK: Schema

    private static func migrate(_ db: OpaquePointer?) {
        exec(db, """
        CREATE TABLE IF NOT EXISTS chunk (
          id TEXT PRIMARY KEY, idx INTEGER, wall_start REAL, file_offset REAL, duration REAL,
          peak_db REAL, mean_db REAL, audio_file TEXT, status TEXT,
          speech_conf REAL, confirmed_seconds REAL, transcript TEXT, embedding BLOB
        )
        """)
        let columns = columnNames(db, table: "chunk")
        if columns.contains("wav_file") { exec(db, "ALTER TABLE chunk RENAME COLUMN wav_file TO audio_file") }
        if !columns.contains("embedding") { exec(db, "ALTER TABLE chunk ADD COLUMN embedding BLOB") }
        exec(db, "CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(id UNINDEXED, text, tokenize='porter unicode61')")
        exec(db, """
        CREATE TABLE IF NOT EXISTS ledger (
          id TEXT PRIMARY KEY, ts REAL, kind TEXT, query TEXT, tier TEXT, reason TEXT, left_device INTEGER,
          model TEXT, is_stub INTEGER, snippets_json TEXT, body_bytes INTEGER, response TEXT,
          prompt_tokens INTEGER, completion_tokens INTEGER, latency_ms REAL, status TEXT, error TEXT
        )
        """)
        if !columnNames(db, table: "ledger").contains("masked_names") { exec(db, "ALTER TABLE ledger ADD COLUMN masked_names INTEGER DEFAULT 0") }
        exec(db, "CREATE TABLE IF NOT EXISTS day_digest (id INTEGER PRIMARY KEY, ts REAL, json TEXT, model TEXT, is_stub INTEGER)")
    }

    private static func columnNames(_ db: OpaquePointer?, table: String) -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var names: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 1) { names.insert(String(cString: c)) }
        }
        return names
    }

    @discardableResult
    private static func exec(_ db: OpaquePointer?, _ sql: String) -> Bool {
        let ok = sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
        if !ok { Log.app.error("sqlite exec failed: \(String(cString: sqlite3_errmsg(db)))") }
        return ok
    }

    // MARK: Chunks

    /// Inserts or updates a chunk. The embedding column is deliberately untouched on update.
    func upsert(_ c: ChunkRecord) {
        var stmt: OpaquePointer?
        let sql = """
        INSERT INTO chunk (id, idx, wall_start, file_offset, duration, peak_db, mean_db, audio_file, status,
                           speech_conf, confirmed_seconds, transcript)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET idx=excluded.idx, wall_start=excluded.wall_start,
          file_offset=excluded.file_offset, duration=excluded.duration, peak_db=excluded.peak_db,
          mean_db=excluded.mean_db, audio_file=excluded.audio_file, status=excluded.status,
          speech_conf=excluded.speech_conf, confirmed_seconds=excluded.confirmed_seconds,
          transcript=excluded.transcript
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.app.error("upsert prepare failed: \(String(cString: sqlite3_errmsg(self.db)))")
            return
        }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, c.id, -1, transient)
        sqlite3_bind_int(stmt, 2, Int32(c.index))
        sqlite3_bind_double(stmt, 3, c.wallStart)
        sqlite3_bind_double(stmt, 4, c.fileOffset)
        sqlite3_bind_double(stmt, 5, c.duration)
        sqlite3_bind_double(stmt, 6, c.peakDb)
        sqlite3_bind_double(stmt, 7, c.meanDb)
        sqlite3_bind_text(stmt, 8, c.audioFile, -1, transient)
        sqlite3_bind_text(stmt, 9, c.status.rawValue, -1, transient)
        if let conf = c.speechConfidence { sqlite3_bind_double(stmt, 10, conf) } else { sqlite3_bind_null(stmt, 10) }
        sqlite3_bind_double(stmt, 11, c.confirmedSeconds)
        if let t = c.transcript { sqlite3_bind_text(stmt, 12, t, -1, transient) } else { sqlite3_bind_null(stmt, 12) }
        if sqlite3_step(stmt) != SQLITE_DONE { Log.app.error("upsert failed") }
    }

    func all() -> [ChunkRecord] {
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, idx, wall_start, file_offset, duration, peak_db, mean_db, audio_file, status,
               speech_conf, confirmed_seconds, transcript FROM chunk ORDER BY idx
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var rows: [ChunkRecord] = []
        func text(_ i: Int32) -> String? { sqlite3_column_text(stmt, i).map { String(cString: $0) } }
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(ChunkRecord(
                id: text(0) ?? "", index: Int(sqlite3_column_int(stmt, 1)),
                wallStart: sqlite3_column_double(stmt, 2), fileOffset: sqlite3_column_double(stmt, 3),
                duration: sqlite3_column_double(stmt, 4), peakDb: sqlite3_column_double(stmt, 5),
                meanDb: sqlite3_column_double(stmt, 6), audioFile: text(7) ?? "",
                status: ChunkStatus(rawValue: text(8) ?? "") ?? .failed,
                speechConfidence: sqlite3_column_type(stmt, 9) == SQLITE_NULL ? nil : sqlite3_column_double(stmt, 9),
                confirmedSeconds: sqlite3_column_double(stmt, 10), transcript: text(11)
            ))
        }
        return rows
    }

    // MARK: Search index

    /// Stores the normalized text in FTS5 and the embedding on the chunk row.
    func index(id: String, normalizedText: String, embedding: [Float]?) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?

        if sqlite3_prepare_v2(db, "DELETE FROM chunk_fts WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, transient)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)

        stmt = nil
        if sqlite3_prepare_v2(db, "INSERT INTO chunk_fts (id, text) VALUES (?, ?)", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, transient)
            sqlite3_bind_text(stmt, 2, normalizedText, -1, transient)
            if sqlite3_step(stmt) != SQLITE_DONE { Log.app.error("fts insert failed") }
        }
        sqlite3_finalize(stmt)

        stmt = nil
        if sqlite3_prepare_v2(db, "UPDATE chunk SET embedding = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            if let embedding {
                let data = Embedder.serialize(embedding)
                _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32(data.count), transient) }
            } else {
                sqlite3_bind_null(stmt, 1)
            }
            sqlite3_bind_text(stmt, 2, id, -1, transient)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    /// BM25-ranked FTS5 matches. `tokens` are OR-joined; higher score is better.
    func ftsSearch(tokens: [String], limit: Int = 20) -> [(id: String, score: Double)] {
        guard !tokens.isEmpty else { return [] }
        let match = tokens.map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"" }.joined(separator: " OR ")
        var stmt: OpaquePointer?
        let sql = "SELECT id, bm25(chunk_fts) FROM chunk_fts WHERE chunk_fts MATCH ? ORDER BY bm25(chunk_fts) LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.app.error("fts prepare failed: \(String(cString: sqlite3_errmsg(self.db)))")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, match, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(stmt, 2, Int32(limit))
        var out: [(String, Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0) else { continue }
            out.append((String(cString: c), -sqlite3_column_double(stmt, 1)))   // bm25() is lower-is-better and negative
        }
        return out
    }

    func embeddings() -> [String: [Float]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, embedding FROM chunk WHERE embedding IS NOT NULL", -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var out: [String: [Float]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let c = sqlite3_column_text(stmt, 0), let blob = sqlite3_column_blob(stmt, 1) else { continue }
            out[String(cString: c)] = Embedder.deserialize(Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 1))))
        }
        return out
    }

    /// Ids that already have an FTS row, used to backfill chunks stored before the index existed.
    func indexedIDs() -> Set<String> {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM chunk_fts", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var ids: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) { ids.insert(String(cString: c)) }
        }
        return ids
    }

    // MARK: Housekeeping

    /// Deletes every row, index entry and audio file.
    func reset() {
        Self.exec(db, "DELETE FROM chunk")
        Self.exec(db, "DELETE FROM chunk_fts")
        Self.exec(db, "DELETE FROM day_digest")   // the digest summarizes the chunks; the ledger is an audit trail and stays
        let files = (try? FileManager.default.contentsOfDirectory(at: chunksDirectory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    func write(audio: Data, named file: String) throws {
        try audio.write(to: chunksDirectory.appending(path: file), options: .atomic)
    }

    // MARK: Privacy ledger

    func upsertLedger(_ e: LedgerEntry) {
        var stmt: OpaquePointer?
        let sql = """
        INSERT OR REPLACE INTO ledger (id, ts, kind, query, tier, reason, left_device, model, is_stub, snippets_json,
          body_bytes, response, prompt_tokens, completion_tokens, latency_ms, status, error, masked_names)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let snippetsJSON = (try? String(data: JSONEncoder().encode(e.snippets), encoding: .utf8)) ?? "[]"
        sqlite3_bind_text(stmt, 1, e.id, -1, t)
        sqlite3_bind_double(stmt, 2, e.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, e.kind.rawValue, -1, t)
        sqlite3_bind_text(stmt, 4, e.query, -1, t)
        sqlite3_bind_text(stmt, 5, e.tier.rawValue, -1, t)
        sqlite3_bind_text(stmt, 6, e.reason, -1, t)
        sqlite3_bind_int(stmt, 7, e.leftDevice ? 1 : 0)
        sqlite3_bind_text(stmt, 8, e.model, -1, t)
        sqlite3_bind_int(stmt, 9, e.isStub ? 1 : 0)
        sqlite3_bind_text(stmt, 10, snippetsJSON, -1, t)
        sqlite3_bind_int(stmt, 11, Int32(e.bodyBytes))
        sqlite3_bind_text(stmt, 12, e.response, -1, t)
        sqlite3_bind_int(stmt, 13, Int32(e.promptTokens))
        sqlite3_bind_int(stmt, 14, Int32(e.completionTokens))
        sqlite3_bind_double(stmt, 15, e.latencyMs)
        sqlite3_bind_text(stmt, 16, e.status.rawValue, -1, t)
        sqlite3_bind_text(stmt, 17, e.error, -1, t)
        sqlite3_bind_int(stmt, 18, Int32(e.maskedNames))
        if sqlite3_step(stmt) != SQLITE_DONE { Log.app.error("ledger upsert failed") }
    }

    /// Newest first.
    func ledgerEntries() -> [LedgerEntry] {
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, ts, kind, query, tier, reason, left_device, model, is_stub, snippets_json, body_bytes, response,
               prompt_tokens, completion_tokens, latency_ms, status, error, masked_names FROM ledger ORDER BY ts DESC
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        var out: [LedgerEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var e = LedgerEntry(query: text(3), tier: Tier(rawValue: text(4)) ?? .local)
            e.id = text(0)
            e.timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            e.kind = LedgerEntry.Kind(rawValue: text(2)) ?? .ask
            e.reason = text(5)
            e.leftDevice = sqlite3_column_int(stmt, 6) != 0
            e.model = text(7)
            e.isStub = sqlite3_column_int(stmt, 8) != 0
            e.snippets = (try? JSONDecoder().decode([Snippet].self, from: Data(text(9).utf8))) ?? []
            e.bodyBytes = Int(sqlite3_column_int(stmt, 10))
            e.response = text(11)
            e.promptTokens = Int(sqlite3_column_int(stmt, 12))
            e.completionTokens = Int(sqlite3_column_int(stmt, 13))
            e.latencyMs = sqlite3_column_double(stmt, 14)
            e.status = LedgerEntry.Status(rawValue: text(15)) ?? .ok
            e.error = text(16)
            e.maskedNames = Int(sqlite3_column_int(stmt, 17))
            out.append(e)
        }
        return out
    }

    func clearLedger() { Self.exec(db, "DELETE FROM ledger") }

    // MARK: Day digest

    func saveDigest(json: String, model: String, isStub: Bool) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO day_digest (id, ts, json, model, is_stub) VALUES (1,?,?,?,?)", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, json, -1, t)
        sqlite3_bind_text(stmt, 3, model, -1, t)
        sqlite3_bind_int(stmt, 4, isStub ? 1 : 0)
        sqlite3_step(stmt)
    }

    func loadDigest() -> (json: String, model: String, isStub: Bool)? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT json, model, is_stub FROM day_digest WHERE id = 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, let j = sqlite3_column_text(stmt, 0) else { return nil }
        return (String(cString: j), sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "", sqlite3_column_int(stmt, 2) != 0)
    }
}
