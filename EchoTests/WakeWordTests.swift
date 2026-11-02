import Foundation
import Testing
@testable import Echo

struct WakeWordTests {
    @Test(arguments: [
        ("Hey Echo, what did Mister Brennan say about the rent?", "what did Mister Brennan say about the rent?"),
        ("hey echo what did I promise today", "what did I promise today"),
        ("Hey, Echo. When is the plumber coming?", "When is the plumber coming?"),
        ("Okay Echo, summarize my day", "summarize my day"),
        ("So hey echo: remind me what the vendor said", "remind me what the vendor said"),
        ("Hey Eco what time is the dentist", "what time is the dentist"),
        ("Hey Echo", ""),
        ("hey echo.", ""),
    ])
    func theWakePhraseIsRecognizedWithItsQuestion(_ heard: String, _ question: String) {
        #expect(WakeWord.question(in: heard) == question)
    }

    @Test(arguments: [
        "I heard an echo in the hallway.", "Hey Maya, how is the echo cancellation going?", "The echo hey was loud.",
        "Echo is a nice name for it.", "Say hey to Echo for me", "", "Hey there, what's up?", "We should talk about the echo chamber."])
    func conversationThatMerelyMentionsEchoIsLeftAlone(_ heard: String) {
        #expect(WakeWord.question(in: heard) == nil)
    }

    @Test func aCommandWithItsQuestionIsAnsweredAndNotKept() {
        var gate = WakeWordGate()
        #expect(gate.decide(transcript: "Hey Echo, what did I promise today?") == .question("what did I promise today?"))
        #expect(gate.decide(transcript: "Let's get lunch.") == .conversation)
    }

    @Test func aBareWakePhraseTakesTheNextSnippetAsTheQuestion() {
        var gate = WakeWordGate()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(gate.decide(transcript: "Hey Echo", now: t0) == .listening)
        #expect(gate.decide(transcript: "when is the plumber coming", now: t0.addingTimeInterval(6)) == .question("when is the plumber coming"))
        #expect(gate.decide(transcript: "and then we left", now: t0.addingTimeInterval(8)) == .conversation, "it only waits for one")
    }

    @Test func aBareWakePhraseGivesUpAfterAWhile() {
        var gate = WakeWordGate()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        _ = gate.decide(transcript: "Hey Echo", now: t0)
        #expect(gate.decide(transcript: "we were talking about lunch", now: t0.addingTimeInterval(WakeWordGate.patience + 1)) == .conversation)
    }

    @Test func nothingHeardIsConversation() {
        var gate = WakeWordGate()
        #expect(gate.decide(transcript: nil) == .conversation && gate.decide(transcript: "   ") == .conversation)
    }
}

struct LiveCaptureTests {
    @Test func blocksOfAnySizeBecomeWholeFrames() {
        var assembler = FrameAssembler(frameSamples: 480)
        #expect(assembler.push(Array(repeating: 1, count: 100)).isEmpty)
        let frames = assembler.push(Array(repeating: 2, count: 1_000))   // 1100 in all: two frames and 140 left over
        #expect(frames.count == 2 && frames.allSatisfy { $0.count == 480 })
        #expect(frames[0].prefix(100).allSatisfy { $0 == 1 } && frames[0][100] == 2)
        #expect(assembler.push(Array(repeating: 3, count: 340)).count == 1)
    }

    /// Live audio arrives in blocks the size of the microphone's buffer, not the detector's frame. It must come out as the
    /// same speech segments either way.
    @Test func liveBlocksFindTheSameSpeechAsWholeFrames() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Echo Watch App/Resources/demo_day_prev.wav")
        let wav = try WAV.read(url)
        let samples = Array(wav.samples.prefix(16_000 * 90))
        let direct = EnergyVAD()
        var expected: [SpeechSegment] = []
        var i = 0
        while i + 480 <= samples.count { if let s = direct.push(Array(samples[i..<i + 480])) { expected.append(s) }; i += 480 }
        let live = LiveSegmenter()
        var got: [SpeechSegment] = []
        var cursor = 0
        let sizes = [1_000, 777, 2_048, 333, 4_000]
        var k = 0
        while cursor < samples.count {
            let n = min(sizes[k % sizes.count], samples.count - cursor)
            got += live.push(Array(samples[cursor..<cursor + n]))
            cursor += n; k += 1
        }
        #expect(!expected.isEmpty && got.count == expected.count)
        #expect(zip(got, expected).allSatisfy { $0.startSample == $1.startSample && $0.samples.count == $1.samples.count })
        #expect(live.level >= 0 && live.level <= 1)
    }

    @Test func liveMomentsAreStampedFromTheClock() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let origin = Date(timeIntervalSince1970: 1_800_000_000)   // a fixed instant
        let midnight = cal.startOfDay(for: origin)
        let since = origin.timeIntervalSince(midnight)
        #expect(LiveClock.secondsSinceMidnight(origin, calendar: cal) == since)
        #expect(LiveClock.wallSeconds(origin: origin, offset: 90, calendar: cal) == (since + 90).truncatingRemainder(dividingBy: 86_400))
        #expect(LiveClock.index(wallSeconds: 3_600) == 36_000)
        #expect(LiveClock.index(wallSeconds: 3_600.5) > LiveClock.index(wallSeconds: 3_600))
    }
}
