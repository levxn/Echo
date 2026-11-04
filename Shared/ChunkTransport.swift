import Foundation

/// Metadata the watch attaches to each chunk of audio.
nonisolated struct ChunkMeta: Codable, Sendable, Equatable {
    let id: String
    let index: Int
    let wallStart: Double      // seconds since midnight (demo clock)
    let fileOffset: Double     // seconds into the watch's recording
    let duration: Double
    let sampleRate: Int
    let peakDb: Double
    let meanDb: Double
    let sampleCount: Int
    /// Where the watch was when it heard this (coarse), when it knew.
    var coordinate: Coordinate? = nil
}

nonisolated enum Wire {
    static let typeKey = "type"
    static let session = "session"       // watch -> phone: replay started / finished
    static let stateKey = "state"        // "started" | "finished" | "paused" | "resumed"
    static let recordedKey = "recorded"  // seconds of audio the watch has processed so far
    static let totalKey = "total"        // seconds in the whole recording
    static let dayOffsetKey = "dayOffset" // with "started": which day this recording is for (0 = today, -7 = a week ago)
    static let widgetKey = "widget"      // phone -> watch (application context): the encoded WidgetSnapshot for the complication
    static let okKey = "ok"

    /// `sendMessageData` accepts 64 KB and rejects 80 KB in the simulator; stay safely under.
    static let maxMessage = 60_000
}

/// A message carrying several AAC-encoded chunks.
///
/// Layout: magic 0xEC, version 2, count u16, recorded f64, then per chunk
/// `metaLen u32, meta JSON, audioLen u32, audio (m4a)`.
///
/// Simulator findings (Day 0/1): `transferFile` never delivers between paired sims, and every
/// `sendMessageData` costs ~1 s regardless of size with no gain from concurrency, so chunks are
/// compressed and bundled to keep the message count low.
nonisolated enum ChunkBundle {
    static let magic: UInt8 = 0xEC
    static let version: UInt8 = 2
    static let headerSize = 12

    struct Entry: Equatable {
        let meta: ChunkMeta
        let audio: Data
    }

    /// One chunk's wire bytes, ready to be concatenated into a bundle.
    static func encodeEntry(_ entry: Entry) -> Data? {
        guard let metaJSON = try? JSONEncoder().encode(entry.meta) else { return nil }
        var out = Data()
        out.append(le32(metaJSON.count)); out.append(metaJSON)
        out.append(le32(entry.audio.count)); out.append(entry.audio)
        return out
    }

    static func bundle(encodedEntries: [Data], recorded: Double) -> Data {
        var out = Data([magic, version])
        withUnsafeBytes(of: UInt16(encodedEntries.count).littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: recorded.bitPattern.littleEndian) { out.append(contentsOf: $0) }
        encodedEntries.forEach { out.append($0) }
        return out
    }

    static func decode(_ data: Data) -> (entries: [Entry], recorded: Double)? {
        let d = [UInt8](data)
        guard d.count >= headerSize, d[0] == magic, d[1] == version else { return nil }
        let count = Int(d[2]) | Int(d[3]) << 8
        var bits: UInt64 = 0
        for i in 0..<8 { bits |= UInt64(d[4 + i]) << UInt64(8 * i) }
        let recorded = Double(bitPattern: bits)

        var pos = headerSize
        func readLen() -> Int? {
            guard pos + 4 <= d.count else { return nil }
            defer { pos += 4 }
            return Int(d[pos]) | Int(d[pos + 1]) << 8 | Int(d[pos + 2]) << 16 | Int(d[pos + 3]) << 24
        }
        var entries: [Entry] = []
        for _ in 0..<count {
            guard let metaLen = readLen(), pos + metaLen <= d.count,
                  let meta = try? JSONDecoder().decode(ChunkMeta.self, from: Data(d[pos..<pos + metaLen])) else { return nil }
            pos += metaLen
            guard let audioLen = readLen(), pos + audioLen <= d.count else { return nil }
            entries.append(Entry(meta: meta, audio: Data(d[pos..<pos + audioLen])))
            pos += audioLen
        }
        return pos == d.count ? (entries, recorded) : nil
    }

    private static func le32(_ v: Int) -> Data {
        var x = UInt32(v).littleEndian
        return Data(bytes: &x, count: 4)
    }
}

extension Array where Element == Int16 {
    nonisolated var pcmData: Data { withUnsafeBufferPointer { Data(buffer: $0) } }
}

extension Data {
    nonisolated var int16Samples: [Int16] {
        let count = self.count / 2
        return [Int16](unsafeUninitializedCapacity: count) { buf, n in
            withUnsafeBytes { raw in
                for i in 0..<count {
                    buf[i] = Int16(bitPattern: raw.loadUnaligned(fromByteOffset: i * 2, as: UInt16.self).littleEndian)
                }
            }
            n = count
        }
    }
}
