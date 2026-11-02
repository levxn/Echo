import AVFoundation
import Foundation

/// Reads a stored moment's audio back as 16 kHz mono samples, the form voiceprints are made from.
nonisolated enum AudioDecoder {
    static func pcm16k(url: URL) -> [Int16]? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return nil }
        do { try file.read(into: buffer) } catch { return nil }
        guard let channels = buffer.floatChannelData else { return nil }
        let frames = Int(buffer.frameLength), count = Int(buffer.format.channelCount)
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<count { for i in 0..<frames { mono[i] += channels[c][i] / Float(count) } }
        let rate = buffer.format.sampleRate
        let target = Double(VoicePrint.rate)
        var resampled = mono
        if abs(rate - target) > 1 {   // linear resampling is plenty for a voiceprint
            let n = Int(Double(frames) * target / rate)
            resampled = (0..<n).map { i in
                let position = Double(i) * rate / target
                let a = Int(position), b = min(a + 1, frames - 1)
                let fraction = Float(position - Double(a))
                return mono[a] * (1 - fraction) + mono[b] * fraction
            }
        }
        return resampled.map { Int16(max(-1, min(1, $0)) * 32767) }
    }

    /// The voiceprint of a stored moment's audio, or nil if there is too little speech.
    static func voicePrint(url: URL) -> VoicePrint? { pcm16k(url: url).flatMap(VoicePrint.make(from:)) }
}
