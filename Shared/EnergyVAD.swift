import Foundation

nonisolated struct VADConfig: Sendable {
    var sampleRate = 16_000
    var frameSamples = 480            // 30 ms
    var marginDb = 9.0                // speech must exceed the noise floor by this much
    var minSpeechDb = -50.0           // absolute floor so digital silence never triggers
    var startFrames = 3               // consecutive voiced frames to open a segment
    var hangoverFrames = 20           // 600 ms of non-voiced frames before closing
    var preRollSeconds = 2.0          // audio prepended from the ring buffer
    var minSegmentSeconds = 0.8
    var maxSegmentSeconds = 30.0
    var floorRise = 0.01              // how fast the noise floor follows a rising background
    var floorFall = 0.2               // ... and a falling one

    var preRollFrames: Int { Int((preRollSeconds * Double(sampleRate) / Double(frameSamples)).rounded(.up)) }
}

nonisolated struct SpeechSegment: Sendable {
    let startSample: Int
    let samples: [Int16]
    let peakDb: Double
    let meanDb: Double
    let sampleRate: Int

    var startSeconds: Double { Double(startSample) / Double(sampleRate) }
    var duration: Double { Double(samples.count) / Double(sampleRate) }
}

/// Stage-1 voice activity detector: lenient energy gate with an adaptive noise floor,
/// hysteresis, and a 2 s pre-roll ring buffer so the first word of a sentence is never clipped.
/// Deliberately favors recall; the phone's stage-2 classifier rejects non-speech bursts.
nonisolated final class EnergyVAD {
    let config: VADConfig

    private(set) var isSpeaking = false
    private(set) var currentDb = -100.0
    private(set) var noiseFloorDb = -60.0

    private var frameIndex = 0
    private var ring: [(index: Int, samples: [Int16])] = []
    private var voicedRun = 0
    private var silentRun = 0
    private var firstVoicedIndex = 0
    private var lastSegmentEndFrame = 0
    private var current: [Int16] = []
    private var currentStartFrame = 0
    private var peakDb = -100.0
    private var dbSum = 0.0
    private var dbCount = 0
    private var primed = false

    init(config: VADConfig = VADConfig()) { self.config = config }

    static func db(of frame: ArraySlice<Int16>) -> Double {
        guard !frame.isEmpty else { return -100 }
        var sum = 0.0
        for s in frame { let v = Double(s); sum += v * v }
        let rms = (sum / Double(frame.count)).squareRoot()
        return rms < 1 ? -100 : 20 * log10(rms / 32768)
    }

    /// Feed exactly `config.frameSamples` samples. Returns a segment when one closes.
    func push(_ frame: [Int16]) -> SpeechSegment? {
        precondition(frame.count == config.frameSamples)
        let index = frameIndex
        frameIndex += 1

        let db = Self.db(of: frame[...])
        currentDb = db
        if !primed { noiseFloorDb = db; primed = true }

        ring.append((index, frame))
        let keep = config.preRollFrames + config.startFrames + 1
        if ring.count > keep { ring.removeFirst(ring.count - keep) }

        let voiced = db > max(noiseFloorDb + config.marginDb, config.minSpeechDb)

        if !voiced && !isSpeaking {
            // Only track the background when nothing speech-like is happening.
            let k = db < noiseFloorDb ? config.floorFall : config.floorRise
            noiseFloorDb += (db - noiseFloorDb) * k
        }

        if !isSpeaking {
            if voiced {
                if voicedRun == 0 { firstVoicedIndex = index }
                voicedRun += 1
                if voicedRun >= config.startFrames { open(at: index) }
            } else {
                voicedRun = 0
            }
            return nil
        }

        current.append(contentsOf: frame)
        if voiced {
            silentRun = 0
            peakDb = max(peakDb, db); dbSum += db; dbCount += 1
        } else {
            silentRun += 1
        }

        if silentRun >= config.hangoverFrames { return close(endFrame: index) }
        if Double(current.count) >= config.maxSegmentSeconds * Double(config.sampleRate) {
            return close(endFrame: index)
        }
        return nil
    }

    /// Close any open segment at end of input.
    func flush() -> SpeechSegment? {
        guard isSpeaking else { return nil }
        return close(endFrame: frameIndex - 1)
    }

    private func open(at index: Int) {
        let wanted = firstVoicedIndex - config.preRollFrames
        let startFrame = max(lastSegmentEndFrame, wanted)
        current = ring.filter { $0.index >= startFrame && $0.index <= index }.flatMap(\.samples)
        currentStartFrame = max(startFrame, ring.first?.index ?? startFrame)
        isSpeaking = true
        silentRun = 0
        voicedRun = 0
        peakDb = db(ofRingFrom: firstVoicedIndex, to: index).peak
        let d = db(ofRingFrom: firstVoicedIndex, to: index)
        dbSum = d.sum; dbCount = d.count
    }

    private func db(ofRingFrom a: Int, to b: Int) -> (peak: Double, sum: Double, count: Int) {
        var peak = -100.0, sum = 0.0, n = 0
        for f in ring where f.index >= a && f.index <= b {
            let d = Self.db(of: f.samples[...])
            peak = max(peak, d); sum += d; n += 1
        }
        return (peak, sum, n)
    }

    private func close(endFrame: Int) -> SpeechSegment? {
        defer {
            isSpeaking = false
            current = []
            silentRun = 0
            voicedRun = 0
            lastSegmentEndFrame = endFrame + 1
        }
        let minSamples = Int(config.minSegmentSeconds * Double(config.sampleRate))
        guard current.count >= minSamples else { return nil }
        return SpeechSegment(
            startSample: currentStartFrame * config.frameSamples,
            samples: current,
            peakDb: peakDb,
            meanDb: dbCount > 0 ? dbSum / Double(dbCount) : peakDb,
            sampleRate: config.sampleRate
        )
    }
}
