import Foundation

/// Metadata the watch sends ahead of a chunk's audio.
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
}

/// Wire format shared by the watch sender and the phone receiver.
///
/// Simulator finding (Day 0): `transferFile` never delivers between paired sims, but
/// `sendMessageData` does (payloads of ~20 KB work, 100 KB fail). Chunks are therefore sent as
/// `begin` (dictionary) -> N framed data packets -> `end` (dictionary).
nonisolated enum Wire {
    static let typeKey = "type"
    static let metaKey = "meta"
    static let indexKey = "index"
    static let bytesKey = "bytes"
    static let packetsKey = "packets"
    static let begin = "begin"
    static let end = "end"

    static let magic: UInt8 = 0xEC
    static let version: UInt8 = 1
    static let headerSize = 10
    static let payloadSize = 16_000

    /// Splits PCM bytes into framed packets: magic, version, chunkIndex u32, seq u16, total u16.
    static func packets(chunkIndex: Int, pcm: Data, payloadSize: Int = Wire.payloadSize) -> [Data] {
        let total = max(1, (pcm.count + payloadSize - 1) / payloadSize)
        return (0..<total).map { seq in
            var packet = Data([magic, version])
            withUnsafeBytes(of: UInt32(chunkIndex).littleEndian) { packet.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt16(seq).littleEndian) { packet.append(contentsOf: $0) }
            withUnsafeBytes(of: UInt16(total).littleEndian) { packet.append(contentsOf: $0) }
            packet.append(pcm.subdata(in: seq * payloadSize..<min(pcm.count, (seq + 1) * payloadSize)))
            return packet
        }
    }

    struct Header: Equatable {
        let chunkIndex: Int
        let seq: Int
        let total: Int
    }

    static func parse(_ packet: Data) -> (header: Header, payload: Data)? {
        guard packet.count >= headerSize, packet[packet.startIndex] == magic,
              packet[packet.startIndex + 1] == version else { return nil }
        let b = packet.startIndex
        func u16(_ at: Int) -> Int { Int(packet[b + at]) | Int(packet[b + at + 1]) << 8 }
        let index = u16(2) | u16(4) << 16
        return (Header(chunkIndex: index, seq: u16(6), total: u16(8)), packet.subdata(in: (b + headerSize)..<packet.endIndex))
    }
}

/// Reassembles one chunk from framed packets, tolerating reordering and duplicates.
nonisolated struct ChunkAssembler {
    private var parts: [Int: Data] = [:]
    private(set) var total = 0
    private(set) var chunkIndex: Int?

    var isComplete: Bool { total > 0 && parts.count == total }
    var receivedBytes: Int { parts.values.reduce(0) { $0 + $1.count } }

    @discardableResult
    mutating func add(_ packet: Data) -> Bool {
        guard let (h, payload) = Wire.parse(packet) else { return false }
        if let chunkIndex, chunkIndex != h.chunkIndex { return false }
        chunkIndex = h.chunkIndex
        total = h.total
        parts[h.seq] = payload
        return true
    }

    func assemble() -> Data? {
        guard isComplete else { return nil }
        var out = Data()
        for seq in 0..<total { out.append(parts[seq]!) }
        return out
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
