import Foundation

/// Dev hook for screenshots and checks: `-seed-transcripts /path/demo_transcripts.json` stores those moments as today's day, with the
/// search index, without the watch having to replay anything. (The audio files are not there, so Play does nothing.)
enum DevSeed {
    private struct Row: Decodable {
        let id: String
        let index: Int
        let wallStart: Double
        let fileOffset: Double
        let duration: Double
        let peakDb: Double
        let meanDb: Double
        let audioFile: String
        let speechConfidence: Double
        let confirmedSeconds: Double
        let transcript: String
    }

    @discardableResult
    static func load(path: String, into store: ChunkStore, day: String = DayID.today(), idSuffix: String = "") async -> Int {
        guard let data = FileManager.default.contents(atPath: path), let rows = try? JSONDecoder().decode([Row].self, from: data) else { return 0 }
        for r in rows {
            var record = ChunkRecord(id: r.id + idSuffix, index: r.index, wallStart: r.wallStart, fileOffset: r.fileOffset, duration: r.duration, peakDb: r.peakDb,
                                     meanDb: r.meanDb, audioFile: r.audioFile, status: .stored, speechConfidence: r.speechConfidence,
                                     confirmedSeconds: r.confirmedSeconds, transcript: r.transcript)
            record.dayId = day
            await store.upsert(record)
            await store.index(id: r.id + idSuffix, normalizedText: TextNormalizer.normalized(r.transcript), embedding: Embedder.vector(for: r.transcript))
        }
        return rows.count
    }
}
