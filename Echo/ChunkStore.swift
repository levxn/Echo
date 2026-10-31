import Foundation
import os
import SQLite3

/// Thin SQLite wrapper. Day 1 only needs the `chunk` table; FTS5 and vectors arrive on Day 2.
actor ChunkStore {
    private var db: OpaquePointer?
    let chunksDirectory: URL

    init() {
        let base = URL.applicationSupportDirectory.appending(path: "Echo", directoryHint: .isDirectory)
        chunksDirectory = base.appending(path: "chunks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: chunksDirectory, withIntermediateDirectories: true)
        let path = base.appending(path: "echo.sqlite").path
        if sqlite3_open(path, &db) != SQLITE_OK { Log.app.error("sqlite open failed") }
        exec("""
        CREATE TABLE IF NOT EXISTS chunk (
          id TEXT PRIMARY KEY, idx INTEGER, wall_start REAL, file_offset REAL, duration REAL,
          peak_db REAL, mean_db REAL, audio_file TEXT, status TEXT,
          speech_conf REAL, confirmed_seconds REAL, transcript TEXT
        )
        """)
    }

    deinit { sqlite3_close(db) }

    func url(for audioFile: String) -> URL { chunksDirectory.appending(path: audioFile) }

    func upsert(_ c: ChunkRecord) {
        var stmt: OpaquePointer?
        let sql = "INSERT OR REPLACE INTO chunk VALUES (?,?,?,?,?,?,?,?,?,?,?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
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
        guard sqlite3_prepare_v2(db, "SELECT * FROM chunk ORDER BY idx", -1, &stmt, nil) == SQLITE_OK else { return [] }
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

    /// Deletes every row and audio file.
    func reset() {
        exec("DELETE FROM chunk")
        let files = (try? FileManager.default.contentsOfDirectory(at: chunksDirectory, includingPropertiesForKeys: nil)) ?? []
        files.forEach { try? FileManager.default.removeItem(at: $0) }
    }

    func write(audio: Data, named file: String) throws {
        try audio.write(to: chunksDirectory.appending(path: file), options: .atomic)
    }

    private func exec(_ sql: String) {
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            Log.app.error("sqlite exec failed: \(String(cString: sqlite3_errmsg(self.db)))")
        }
    }
}
