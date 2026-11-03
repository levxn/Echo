import Foundation
import Testing
@testable import Echo

struct MotionTests {
    @Test func theEqualizerStaysInRangeAndBarsMoveIndependently() {
        for t in stride(from: 0.0, through: 10.0, by: 0.07) {
            for i in 0..<7 { let l = WaveLevels.level(i, at: t); #expect(l >= 0.3 - 1e-9 && l <= 1 + 1e-9) }
        }
        let a = (0..<4).map { WaveLevels.level($0, at: 1.0) }, b = (0..<4).map { WaveLevels.level($0, at: 1.2) }
        #expect(a != b && Set(a.map { ($0 * 1000).rounded() }).count > 2, "moving, and not in step")
        #expect((0..<7).allSatisfy { WaveLevels.resting($0) > 0 && WaveLevels.resting($0) <= 1 })
    }

    @Test func aShortAnswerIsRevealedWordByWord() {
        let s = RevealSchedule(words: 10)
        #expect(s.perWord == RevealSchedule.idealPerWord)
        #expect(s.opacity(ofWord: 0, at: 0) == 0 && s.opacity(ofWord: 0, at: RevealSchedule.fade) == 1)
        #expect(s.opacity(ofWord: 9, at: 0) == 0, "later words are not there yet")
        #expect(s.opacity(ofWord: 9, at: s.duration) > 1 - 1e-9, "and every word is there at the end")
    }

    @Test func aLongAnswerNeverTakesLongerThanTheCap() {
        for words in [1, 2, 30, 80, 200, 1_000] {
            let s = RevealSchedule(words: words)
            #expect(s.duration <= RevealSchedule.maxTotal + 1e-9, "\(words) words take \(s.duration) s")
            #expect(s.opacity(ofWord: words - 1, at: s.duration) > 1 - 1e-9)
        }
        #expect(RevealSchedule(words: 0).duration == 0)
    }

    @Test func eachWordOnlyEverFadesIn() {
        let s = RevealSchedule(words: 25)
        for i in 0..<25 {
            let v = stride(from: 0.0, through: s.duration, by: 0.02).map { s.opacity(ofWord: i, at: $0) }
            #expect(zip(v, v.dropFirst()).allSatisfy { $0 <= $1 })
        }
    }

    @MainActor @Test func anAnswerAlreadyShownIsNotReplayed() {
        let text = "You promised to send the spec \(UUID().uuidString)"
        #expect(!RevealMemory.hasSeen(text))
        RevealMemory.markSeen(text)
        #expect(RevealMemory.hasSeen(text))
    }
}
