import Foundation

/// A short numeric description of how a voice sounds, from one stretch of speech: the average and spread of its MFCCs (the
/// shape of the voice's spectrum) and of its pitch. Two stretches by the same person land close together; different people
/// land apart. Pure Swift: no model, no network, nothing to download.
nonisolated struct VoicePrint: Equatable, Sendable {
    static let rate = 16_000
    static let coefficients = 12          // MFCC 1...12 (0 is loudness, which says nothing about who is talking)
    static let dimensions = coefficients * 2 + 2

    var values: [Float]

    // MARK: Distance

    /// How far apart two voices are, in units of how much voices differ in each dimension. Under `SpeakerBook.threshold` is the
    /// same voice.
    func distance(to other: VoicePrint) -> Float {
        var sum: Float = 0
        for i in 0..<min(values.count, other.values.count) {
            let d = (values[i] - other.values[i]) / Self.scale[i]
            sum += d * d
        }
        return (sum / Float(Self.dimensions)).squareRoot()
    }

    /// How much each dimension varies within one person's speech. Dividing by it makes the dimensions that identify a voice
    /// count and the ones that wobble on their own count less. Measured on the audio the phone really receives, after the
    /// watch's compression (8 voices, 69 moments); `SpeakerTests` checks that the whole thing still separates them.
    static let scale: [Float] = [
        3.385, 1.847, 2.573, 1.770, 0.992, 1.509, 0.949, 0.879, 0.819, 0.718, 0.610, 0.619,
        3.075, 1.156, 1.389, 0.780, 0.883, 0.751, 0.443, 0.523, 0.480, 0.317, 0.354, 0.299,
        0.068, 0.045,
    ]

    // MARK: Storage

    var data: Data { values.withUnsafeBufferPointer { Data(buffer: $0) } }

    init(values: [Float]) { self.values = values }

    init?(data: Data) {
        guard data.count == Self.dimensions * MemoryLayout<Float>.size else { return nil }
        values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // MARK: Making one

    /// From 16 kHz mono samples. Nil when there is too little speech to tell (under about a quarter of a second).
    static func make(from samples: [Int16]) -> VoicePrint? {
        let frames = MFCC.frames(samples)
        guard frames.count >= 25 else { return nil }
        let c = coefficients
        var mean = [Float](repeating: 0, count: c), sq = [Float](repeating: 0, count: c)
        for f in frames {
            for k in 0..<c { mean[k] += f.mfcc[k]; sq[k] += f.mfcc[k] * f.mfcc[k] }
        }
        let n = Float(frames.count)
        var values: [Float] = []
        for k in 0..<c { values.append(mean[k] / n) }
        for k in 0..<c { values.append(max(0, sq[k] / n - (mean[k] / n) * (mean[k] / n)).squareRoot()) }
        let pitches = frames.compactMap(\.pitch).map { log2($0) }
        if pitches.count >= 5 {
            let m = pitches.reduce(0, +) / Float(pitches.count)
            let v = pitches.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Float(pitches.count)
            values += [m, v.squareRoot()]
        } else {
            values += [7, 0.3]   // no steady pitch found: a middling value, so it neither helps nor hurts much
        }
        return VoicePrint(values: values)
    }
}
