import Foundation
import Testing
@testable import Echo

/// Records what it was asked to say and lets the test decide when it finishes.
@MainActor
private final class FakeEngine: SpeechEngine {
    var started: [String] = []
    var stops = 0
    private var finishers: [@MainActor () -> Void] = []

    func start(_ text: String, finished: @escaping @MainActor () -> Void) {
        started.append(text)
        finishers.append(finished)
    }
    func stop() { stops += 1 }
    /// The nth reading ends by itself.
    func finish(_ n: Int) { finishers[n]() }
}

@MainActor
struct SpeakerTests {
    @Test func speakingReadsTidiedTextAndFinishingClearsIt() {
        let engine = FakeEngine()
        let speaker = Speaker(engine: engine)
        speaker.speak("You promised **two** things.\n\nSend the spec.", id: "a")
        #expect(engine.started == ["You promised two things. Send the spec."])
        #expect(speaker.speakingID == "a" && speaker.isSpeaking("a"))
        engine.finish(0)
        #expect(speaker.speakingID == nil)
    }

    @Test func nothingToSayIsIgnored() {
        let engine = FakeEngine()
        let speaker = Speaker(engine: engine)
        speaker.speak("  \n ")
        speaker.speak("")
        #expect(engine.started.isEmpty && speaker.speakingID == nil)
    }

    @Test func startingAnotherAnswerCutsOffTheFirstAndTheStaleEndDoesNotClearTheNewOne() {
        let engine = FakeEngine()
        let speaker = Speaker(engine: engine)
        speaker.speak("First.", id: "one")
        speaker.speak("Second.", id: "two")
        #expect(speaker.speakingID == "two")
        engine.finish(0)   // the first one reports that it ended, late
        #expect(speaker.speakingID == "two", "it must not blank the one now being read")
        engine.finish(1)
        #expect(speaker.speakingID == nil)
    }

    @Test func theButtonStartsThenStops() {
        let engine = FakeEngine()
        let speaker = Speaker(engine: engine)
        speaker.toggle("An answer.", id: "x")
        #expect(speaker.speakingID == "x")
        let stopsBefore = engine.stops
        speaker.toggle("An answer.", id: "x")
        #expect(speaker.speakingID == nil && engine.stops == stopsBefore + 1 && engine.started.count == 1)
    }

    @Test func somethingElseThatWasPlayingIsToldToStop() {
        let engine = FakeEngine()
        let speaker = Speaker(engine: engine)
        var told = 0
        speaker.willSpeak = { told += 1 }
        speaker.speak("Hello there.")
        speaker.speak("")
        #expect(told == 1, "only real speech interrupts a recorded moment")
    }

    @Test func stoppingSilencesAndClears() {
        let engine = FakeEngine()
        let speaker = Speaker(engine: engine)
        speaker.speak("Hello there.")
        speaker.stop()
        #expect(speaker.speakingID == nil)
    }
}
