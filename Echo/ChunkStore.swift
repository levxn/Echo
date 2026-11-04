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
        // Transcripts and audio are encrypted by the OS whenever the phone has not been unlocked since it started; after the first unlock
        // they stay readable, so the watch can still deliver while the phone is locked.
        for folder in [base, chunksDirectory] {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: folder.path)
        }
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
        if !columns.contains("day_id") {
            // Memories used to be a single day. Whatever is stored now was captured today.
            exec(db, "ALTER TABLE chunk ADD COLUMN day_id TEXT")
            exec(db, "UPDATE chunk SET day_id = '\(DayID.today())'")
        }
        exec(db, "CREATE INDEX IF NOT EXISTS chunk_day ON chunk(day_id)")
        if !columns.contains("speaker_id") { exec(db, "ALTER TABLE chunk ADD COLUMN speaker_id TEXT") }
        if !columns.contains("voiceprint") { exec(db, "ALTER TABLE chunk ADD COLUMN voiceprint BLOB") }
        if !columns.contains("lat") { exec(db, "ALTER TABLE chunk ADD COLUMN lat REAL") }
        if !columns.contains("lon") { exec(db, "ALTER TABLE chunk ADD COLUMN lon REAL") }
        exec(db, "CREATE TABLE IF NOT EXISTS place (id TEXT PRIMARY KEY, name TEXT, lat REAL, lon REAL, radius REAL, no_record INTEGER DEFAULT 0, created REAL)")
        exec(db, "CREATE TABLE IF NOT EXISTS journal (day_id TEXT PRIMARY KEY, ts REAL, json TEXT, model TEXT, is_stub INTEGER)")
        exec(db, """
        CREATE TABLE IF NOT EXISTS speaker (
          id TEXT PRIMARY KEY, label TEXT, name TEXT, is_me INTEGER DEFAULT 0, centroid BLOB, count INTEGER, color INTEGER, created REAL
        )
        """)
        exec(db, "CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(id UNINDEXED, text, tokenize='porter unicode61')")
        exec(db, """
        CREATE TABLE IF NOT EXISTS ledger (
          id TEXT PRIMARY KEY, ts REAL, kind TEXT, query TEXT, tier TEXT, reason TEXT, left_device INTEGER,
          model TEXT, is_stub INTEGER, snippets_json TEXT, body_bytes INTEGER, response TEXT,
          prompt_tokens INTEGER, completion_tokens INTEGER, latency_ms REAL, status TEXT, error TEXT
        )
        """)
        exec(db, """
        CREATE TABLE IF NOT EXISTS ask_history (
          id TEXT PRIMARY KEY, ts REAL, question TEXT, short_answer TEXT, source TEXT, via TEXT, detail_json TEXT, ms INTEGER
        )
        """)
        if !columnNames(db, table: "ledger").contains("masked_names") { exec(db, "ALTER TABLE ledger ADD COLUMN masked_names INTEGER DEFAULT 0") }
        if !columnNames(db, table: "ledger").contains("held_back") { exec(db, "ALTER TABLE ledger ADD COLUMN held_back TEXT DEFAULT ''") }
        exec(db, "CREATE TABLE IF NOT EXISTS day_digest (id INTEGER PRIMARY KEY, ts REAL, json TEXT, model TEXT, is_stub INTEGER)")
        if !columnNames(db, table: "day_digest").contains("day_id") {
            exec(db, "ALTER TABLE day_digest ADD COLUMN day_id TEXT")
            exec(db, "UPDATE day_digest SET day_id = '\(DayID.today())'")
        }
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
                           speech_conf, confirmed_seconds, transcript, day_id, speaker_id, lat, lon)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET idx=excluded.idx, wall_start=excluded.wall_start,
          file_offset=excluded.file_offset, duration=excluded.duration, peak_db=excluded.peak_db,
          mean_db=excluded.mean_db, audio_file=excluded.audio_file, status=excluded.status,
          speech_conf=excluded.speech_conf, confirmed_seconds=excluded.confirmed_seconds,
          transcript=excluded.transcript, day_id=excluded.day_id, speaker_id=excluded.speaker_id, lat=excluded.lat, lon=excluded.lon
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
        sqlite3_bind_text(stmt, 13, c.dayId, -1, transient)
        sqlite3_bind_text(stmt, 14, c.speakerId, -1, transient)
        if let spot = c.coordinate { sqlite3_bind_double(stmt, 15, spot.lat); sqlite3_bind_double(stmt, 16, spot.lon) } else { sqlite3_bind_null(stmt, 15); sqlite3_bind_null(stmt, 16) }
        if sqlite3_step(stmt) != SQLITE_DONE { Log.app.error("upsert failed") }
    }

    /// Every moment from every day, oldest day first and in order within a day.
    func all() -> [ChunkRecord] { rows(where: nil) }

    /// The moments of one day (and any from before days existed).
    func all(day: String) -> [ChunkRecord] { rows(where: day) }

    private func rows(where day: String?) -> [ChunkRecord] {
        var stmt: OpaquePointer?
        let filter = day == nil ? "" : "WHERE day_id = ? OR day_id IS NULL OR day_id = ''"
        let sql = """
        SELECT id, idx, wall_start, file_offset, duration, peak_db, mean_db, audio_file, status,
               speech_conf, confirmed_seconds, transcript, day_id, speaker_id, lat, lon FROM chunk \(filter) ORDER BY COALESCE(day_id, ''), idx
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        if let day { sqlite3_bind_text(stmt, 1, day, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
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
                confirmedSeconds: sqlite3_column_double(stmt, 10), transcript: text(11), dayId: text(12) ?? "", speakerId: text(13) ?? "",
                coordinate: sqlite3_column_type(stmt, 14) == SQLITE_NULL ? nil : Coordinate(lat: sqlite3_column_double(stmt, 14), lon: sqlite3_column_double(stmt, 15))
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
        Self.exec(db, "DELETE FROM journal")      // so does the journal
        Self.exec(db, "DELETE FROM day_digest")   // the digest summarizes the chunks; the ledger is an audit trail and stays
        Self.exec(db, "DELETE FROM ask_history")  // the questions and answers are about this day too
        Self.exec(db, "DELETE FROM speaker")      // who sounded like whom is part of what was heard
        let files = (try? FileManager.default.contentsOfDirectory(at: chunksDirectory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    /// Removes one moment: its row (and the embedding on it), its search entry and its audio file. Unknown ids do nothing.
    func delete(id: String) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        var audioFile: String?
        if sqlite3_prepare_v2(db, "SELECT audio_file FROM chunk WHERE id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, id, -1, transient)
            if sqlite3_step(stmt) == SQLITE_ROW, let c = sqlite3_column_text(stmt, 0) { audioFile = String(cString: c) }
        }
        sqlite3_finalize(stmt)
        for sql in ["DELETE FROM chunk WHERE id = ?", "DELETE FROM chunk_fts WHERE id = ?"] {
            stmt = nil
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, transient)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
        if let audioFile { try? FileManager.default.removeItem(at: chunksDirectory.appending(path: audioFile)) }
    }

    /// Removes several moments and anything that cites them (history entries whose answer pointed at them). Returns the
    /// ids that were actually there.
    @discardableResult
    func deleteChunks(ids: [String]) -> [String] {
        let present = Set(all().map(\.id)).intersection(ids)
        for id in present { delete(id: id) }
        deleteHistory(citing: Array(present))
        return Array(present)
    }

    /// Replaces a day: everything captured on it goes (and the history that cited it), so a new session for the same day
    /// starts clean. Other days are untouched. Moments from before days existed count as belonging to it.
    @discardableResult
    func deleteDay(_ day: String) -> [String] {
        let ids = all(day: day).map(\.id)
        for id in ids { delete(id: id) }
        deleteHistory(citing: ids)
        deleteJournal(day: day)
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM day_digest WHERE day_id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, day, -1, transient)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return ids
    }

    /// Removes a stored audio file by name (a moment that was heard but must not be kept).
    func removeAudio(named file: String) { try? FileManager.default.removeItem(at: chunksDirectory.appending(path: file)) }

    // MARK: Places

    func savePlace(_ p: Place) {
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO place (id, name, lat, lon, radius, no_record, created) VALUES (?,?,?,?,?,?,?)", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, p.id, -1, t)
        sqlite3_bind_text(stmt, 2, p.name, -1, t)
        sqlite3_bind_double(stmt, 3, p.coordinate.lat)
        sqlite3_bind_double(stmt, 4, p.coordinate.lon)
        sqlite3_bind_double(stmt, 5, p.radius)
        sqlite3_bind_int(stmt, 6, p.noRecord ? 1 : 0)
        sqlite3_bind_double(stmt, 7, p.created.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    func places() -> [Place] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, name, lat, lon, radius, no_record, created FROM place ORDER BY created", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [Place] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(Place(id: sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "", name: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
                             coordinate: Coordinate(lat: sqlite3_column_double(stmt, 2), lon: sqlite3_column_double(stmt, 3)),
                             radius: sqlite3_column_double(stmt, 4), noRecord: sqlite3_column_int(stmt, 5) != 0,
                             created: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 6))))
        }
        return out
    }

    func deletePlace(id: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM place WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }

    func clearPlaces() { Self.exec(db, "DELETE FROM place") }

    // MARK: Journal

    func saveJournal(json: String, model: String, isStub: Bool, day: String) {
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO journal (day_id, ts, json, model, is_stub) VALUES (?,?,?,?,?)", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, day, -1, t)
        sqlite3_bind_double(stmt, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, json, -1, t)
        sqlite3_bind_text(stmt, 4, model, -1, t)
        sqlite3_bind_int(stmt, 5, isStub ? 1 : 0)
        sqlite3_step(stmt)
    }

    /// Every saved entry, newest day first.
    func journals() -> [(day: String, json: String, model: String, isStub: Bool)] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT day_id, json, model, is_stub FROM journal ORDER BY day_id DESC", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, String, String, Bool)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func t(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
            out.append((t(0), t(1), t(2), sqlite3_column_int(stmt, 3) != 0))
        }
        return out
    }

    func deleteJournal(day: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM journal WHERE day_id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, day, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }

    /// Forgets a day's summary (it described moments that are gone).
    func deleteDigest(day: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM day_digest WHERE day_id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, day, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }

    /// Forgets every day older than `day` (and its digest). Moments from before days existed are never purged. Returns how many.
    @discardableResult
    func purge(before day: String) -> Int {
        let old = all().filter { !$0.dayId.isEmpty && $0.dayId < day }
        for c in old { delete(id: c.id) }
        deleteHistory(citing: old.map(\.id))
        for d in Set(old.map(\.dayId)) { deleteJournal(day: d) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM day_digest WHERE day_id < ? AND day_id != ''", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, day, -1, transient)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        return old.count
    }

    /// The days that have anything stored, newest first, with how many moments each has.
    func days() -> [(day: String, count: Int)] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(day_id, ''), COUNT(*) FROM chunk WHERE status = 'stored' GROUP BY COALESCE(day_id, '') ORDER BY 1 DESC", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, Int)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append((sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? "", Int(sqlite3_column_int(stmt, 1))))
        }
        return out
    }

    func write(audio: Data, named file: String) throws {
        try audio.write(to: chunksDirectory.appending(path: file), options: .atomic)
    }

    // MARK: Voices

    /// Remembers whose voice a moment is, with the voiceprint it was judged by.
    func setVoice(chunkID: String, speakerID: String, print: Data?) {
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE chunk SET speaker_id = ?, voiceprint = ? WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, speakerID, -1, t)
        if let print { _ = print.withUnsafeBytes { sqlite3_bind_blob(stmt, 2, $0.baseAddress, Int32(print.count), t) } } else { sqlite3_bind_null(stmt, 2) }
        sqlite3_bind_text(stmt, 3, chunkID, -1, t)
        sqlite3_step(stmt)
    }

    /// Moves every moment of one voice to another (merging two voices that were the same person).
    func reassignVoice(from old: String, to new: String) {
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE chunk SET speaker_id = ? WHERE speaker_id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, new, -1, t)
        sqlite3_bind_text(stmt, 2, old, -1, t)
        sqlite3_step(stmt)
    }

    func saveSpeaker(_ s: Voice) {
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO speaker (id, label, name, is_me, centroid, count, color, created) VALUES (?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, s.id, -1, t)
        sqlite3_bind_text(stmt, 2, s.label, -1, t)
        if let name = s.name { sqlite3_bind_text(stmt, 3, name, -1, t) } else { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_int(stmt, 4, s.isMe ? 1 : 0)
        let data = s.centroid.data
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 5, $0.baseAddress, Int32(data.count), t) }
        sqlite3_bind_int(stmt, 6, Int32(s.count))
        sqlite3_bind_int(stmt, 7, Int32(s.colorIndex))
        sqlite3_bind_double(stmt, 8, s.created.timeIntervalSince1970)
        sqlite3_step(stmt)
    }

    func speakers() -> [Voice] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id, label, name, is_me, centroid, count, color, created FROM speaker ORDER BY created", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [Voice] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = sqlite3_column_text(stmt, 0).map({ String(cString: $0) }), let blob = sqlite3_column_blob(stmt, 4),
                  let centroid = VoicePrint(data: Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 4)))) else { continue }
            out.append(Voice(id: id, label: sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "",
                               name: sqlite3_column_text(stmt, 2).map { String(cString: $0) }, isMe: sqlite3_column_int(stmt, 3) != 0,
                               centroid: centroid, count: Int(sqlite3_column_int(stmt, 5)), colorIndex: Int(sqlite3_column_int(stmt, 6)),
                               created: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7))))
        }
        return out
    }

    /// Just the voice's row, after its moments were moved to another voice.
    func deleteSpeakerRow(id: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM speaker WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }

    func deleteSpeaker(id: String) {
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for sql in ["DELETE FROM speaker WHERE id = ?", "UPDATE chunk SET speaker_id = '', voiceprint = NULL WHERE speaker_id = ?"] {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, id, -1, t)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: Privacy ledger

    func upsertLedger(_ e: LedgerEntry) {
        var stmt: OpaquePointer?
        let sql = """
        INSERT OR REPLACE INTO ledger (id, ts, kind, query, tier, reason, left_device, model, is_stub, snippets_json,
          body_bytes, response, prompt_tokens, completion_tokens, latency_ms, status, error, masked_names, held_back)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
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
        sqlite3_bind_text(stmt, 19, (try? String(data: JSONEncoder().encode(e.heldBack), encoding: .utf8)) ?? "{}", -1, t)
        if sqlite3_step(stmt) != SQLITE_DONE { Log.app.error("ledger upsert failed") }
    }

    /// Newest first.
    func ledgerEntries() -> [LedgerEntry] {
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, ts, kind, query, tier, reason, left_device, model, is_stub, snippets_json, body_bytes, response,
               prompt_tokens, completion_tokens, latency_ms, status, error, masked_names, held_back FROM ledger ORDER BY ts DESC
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
            e.heldBack = (try? JSONDecoder().decode([String: Int].self, from: Data(text(18).utf8))) ?? [:]
            out.append(e)
        }
        return out
    }

    func clearLedger() { Self.exec(db, "DELETE FROM ledger") }

    /// Blanks what Muse replied on every ledger row. The ledger keeps what was asked and exactly what was sent, but not
    /// the answers about the user's day.
    func redactLedgerResponses() { Self.exec(db, "UPDATE ledger SET response = ''") }

    // MARK: Ask history

    func upsertHistory(_ r: AskRecord) {
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO ask_history (id, ts, question, short_answer, source, via, detail_json, ms) VALUES (?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let detail = (try? String(data: JSONEncoder().encode(r.detail), encoding: .utf8)) ?? "{}"
        sqlite3_bind_text(stmt, 1, r.id, -1, t)
        sqlite3_bind_double(stmt, 2, r.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, r.question, -1, t)
        sqlite3_bind_text(stmt, 4, r.shortAnswer, -1, t)
        sqlite3_bind_text(stmt, 5, r.source.rawValue, -1, t)
        sqlite3_bind_text(stmt, 6, r.via.rawValue, -1, t)
        sqlite3_bind_text(stmt, 7, detail, -1, t)
        sqlite3_bind_int(stmt, 8, Int32(r.milliseconds))
        if sqlite3_step(stmt) != SQLITE_DONE { Log.app.error("history upsert failed") }
        // Keep only the newest `AskHistoryModel.capacity`.
        Self.exec(db, "DELETE FROM ask_history WHERE id NOT IN (SELECT id FROM ask_history ORDER BY ts DESC LIMIT \(AskHistoryModel.capacity))")
    }

    /// Newest first.
    func history(limit: Int = 200) -> [AskRecord] {
        var stmt: OpaquePointer?
        let sql = "SELECT id, ts, question, short_answer, source, via, detail_json, ms FROM ask_history ORDER BY ts DESC LIMIT ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        func text(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
        var out: [AskRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let detail = (try? JSONDecoder().decode(AskDetail.self, from: Data(text(6).utf8))) ?? AskDetail(kind: .note, headline: "")
            out.append(AskRecord(id: text(0), timestamp: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)), question: text(2),
                                 shortAnswer: text(3), source: WatchAnswer.Source(rawValue: text(4)) ?? .none,
                                 via: AskVia(rawValue: text(5)) ?? .typed, detail: detail, milliseconds: Int(sqlite3_column_int(stmt, 7))))
        }
        return out
    }

    func deleteHistory(id: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM ask_history WHERE id = ?", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(stmt)
    }

    func clearHistory() { Self.exec(db, "DELETE FROM ask_history") }

    /// Removes the history entries whose stored answer points at any of these moments (their citations would be dead).
    func deleteHistory(citing chunkIDs: [String]) {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for id in chunkIDs {
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "DELETE FROM ask_history WHERE detail_json LIKE ?", -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_text(stmt, 1, "%\(id)%", -1, transient)
                sqlite3_step(stmt)
            }
            sqlite3_finalize(stmt)
        }
    }

    // MARK: Day digest

    /// One digest per day; saving again replaces that day's.
    func saveDigest(json: String, model: String, isStub: Bool, day: String = DayID.today()) {
        let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "DELETE FROM day_digest WHERE day_id = ?", -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, day, -1, t)
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
        stmt = nil
        guard sqlite3_prepare_v2(db, "INSERT INTO day_digest (ts, json, model, is_stub, day_id) VALUES (?,?,?,?,?)", -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
        sqlite3_bind_text(stmt, 2, json, -1, t)
        sqlite3_bind_text(stmt, 3, model, -1, t)
        sqlite3_bind_int(stmt, 4, isStub ? 1 : 0)
        sqlite3_bind_text(stmt, 5, day, -1, t)
        sqlite3_step(stmt)
    }

    func loadDigest(day: String = DayID.today()) -> (json: String, model: String, isStub: Bool)? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT json, model, is_stub FROM day_digest WHERE day_id = ? ORDER BY ts DESC LIMIT 1", -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, day, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(stmt) == SQLITE_ROW, let j = sqlite3_column_text(stmt, 0) else { return nil }
        return (String(cString: j), sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? "", sqlite3_column_int(stmt, 2) != 0)
    }

    /// Every saved digest, newest day first (for a weekly summary).
    func digests() -> [(day: String, json: String, model: String, isStub: Bool)] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT COALESCE(day_id, ''), json, model, is_stub FROM day_digest ORDER BY day_id DESC", -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [(String, String, String, Bool)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            func t(_ i: Int32) -> String { sqlite3_column_text(stmt, i).map { String(cString: $0) } ?? "" }
            out.append((t(0), t(1), t(2), sqlite3_column_int(stmt, 3) != 0))
        }
        return out
    }
}
