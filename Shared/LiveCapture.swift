import Foundation

/// Turns audio that arrives in blocks of any size into the fixed frames the voice detector takes.
nonisolated struct FrameAssembler: Sendable {
    let frameSamples: Int
    private var pending: [Int16] = []

    init(frameSamples: Int = VADConfig().frameSamples) { self.frameSamples = frameSamples }

    mutating func push(_ samples: [Int16]) -> [[Int16]] {
        pending.append(contentsOf: samples)
        var frames: [[Int16]] = []
        var start = 0
        while pending.count - start >= frameSamples {
            frames.append(Array(pending[start..<start + frameSamples]))
            start += frameSamples
        }
        if start > 0 { pending.removeFirst(start) }
        return frames
    }
}

/// Live audio through the same stage-1 detector the recorded day goes through: blocks in, finished speech segments out.
nonisolated final class LiveSegmenter: @unchecked Sendable {
    private let vad = EnergyVAD()
    private var assembler = FrameAssembler()
    private let lock = NSLock()
    private var db = -100.0
    private var speaking = false

    /// 0...1, for a level meter.
    var level: Double { lock.lock(); defer { lock.unlock() }; return max(0, min(1, (db + 60) / 45)) }
    var isSpeaking: Bool { lock.lock(); defer { lock.unlock() }; return speaking }

    func push(_ samples: [Int16]) -> [SpeechSegment] {
        lock.lock(); defer { lock.unlock() }
        var out: [SpeechSegment] = []
        for frame in assembler.push(samples) {
            if let seg = vad.push(frame) { out.append(seg) }
        }
        db = vad.currentDb
        speaking = vad.isSpeaking
        return out
    }

    /// The segment still open when listening stops, if any.
    func finish() -> SpeechSegment? {
        lock.lock(); defer { lock.unlock() }
        return vad.flush()
    }
}

/// Wall-clock time for audio captured live: the moment listening began plus how far into it a segment starts.
nonisolated enum LiveClock {
    static func secondsSinceMidnight(_ date: Date, calendar: Calendar = .current) -> Double {
        date.timeIntervalSince(calendar.startOfDay(for: date))
    }

    static func wallSeconds(origin: Date, offset: Double, calendar: Calendar = .current) -> Double {
        (secondsSinceMidnight(origin, calendar: calendar) + offset).truncatingRemainder(dividingBy: 86_400)
    }

    /// Live moments have no recording to number them from, and a new listening session must not reuse the last one's numbers
    /// (the phone orders a day by them): a tenth of a second since midnight is unique and in order.
    static func index(wallSeconds: Double) -> Int { Int(wallSeconds * 10) }
}
