import Foundation

/// Minimal 16-bit PCM mono WAV reader/writer. All demo audio is 16 kHz mono Int16.
nonisolated enum WAV {
    enum WAVError: Error { case malformed, unsupported }

    static func encode(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let byteCount = samples.count * 2
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
        data.append("RIFF".data(using: .ascii)!); u32(36 + byteCount)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
        data.append("data".data(using: .ascii)!); u32(byteCount)
        samples.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
        return data
    }

    static func decode(_ data: Data) throws -> (samples: [Int16], sampleRate: Int) {
        guard data.count > 12,
              data.prefix(4) == "RIFF".data(using: .ascii),
              data[8..<12] == "WAVE".data(using: .ascii) else { throw WAVError.malformed }
        func u32(_ at: Int) -> Int {
            Int(data[at]) | Int(data[at + 1]) << 8 | Int(data[at + 2]) << 16 | Int(data[at + 3]) << 24
        }
        func u16(_ at: Int) -> Int { Int(data[at]) | Int(data[at + 1]) << 8 }

        var rate = 0, channels = 0, bits = 0
        var pos = 12
        while pos + 8 <= data.count {
            let id = String(decoding: data[pos..<pos + 4], as: UTF8.self)
            let size = u32(pos + 4)
            let body = pos + 8
            if id == "fmt " {
                guard u16(body) == 1 else { throw WAVError.unsupported }
                channels = u16(body + 2); rate = u32(body + 4); bits = u16(body + 14)
            } else if id == "data" {
                guard channels == 1, bits == 16 else { throw WAVError.unsupported }
                let end = min(body + size, data.count)
                let count = (end - body) / 2
                let samples = [Int16](unsafeUninitializedCapacity: count) { buf, n in
                    data.withUnsafeBytes { raw in
                        for i in 0..<count {
                            buf[i] = Int16(bitPattern: raw.loadUnaligned(fromByteOffset: body + i * 2, as: UInt16.self).littleEndian)
                        }
                    }
                    n = count
                }
                return (samples, rate)
            }
            pos = body + size + (size & 1)
        }
        throw WAVError.malformed
    }

    static func read(_ url: URL) throws -> (samples: [Int16], sampleRate: Int) {
        try decode(Data(contentsOf: url))
    }
}
