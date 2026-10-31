import AVFoundation

/// AAC (m4a) encode for chunk transport. At 16 kHz mono / 20 kbps, AVAudioFile produces roughly
/// 5 KB per second of speech (a sixth of raw PCM), which matters because WatchConnectivity
/// messages cost ~1 s each in the simulator regardless of size.
nonisolated enum AudioCodec {
    static func encodeAAC(samples: [Int16], sampleRate: Int, bitRate: Int = 20_000) -> Data? {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        guard write(samples: samples, sampleRate: sampleRate, bitRate: bitRate, to: url) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// Scoped so the AVAudioFile is released (and the m4a finalized) before the caller reads it.
    private static func write(samples: [Int16], sampleRate: Int, bitRate: Int, to url: URL) -> Bool {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(sampleRate), channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return false }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.int16ChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: bitRate,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: true)
            try file.write(from: buffer)
            return true
        } catch {
            return false
        }
    }

    /// Decoded length in seconds, for tests and sanity checks.
    static func duration(of url: URL) -> Double? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return Double(file.length) / file.fileFormat.sampleRate
    }
}
