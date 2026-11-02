import Foundation
import Testing
@testable import Echo

struct IntentTests {
    private func chunk(_ i: Int, _ text: String, day: String, speaker: String = "") -> ChunkRecord {
        var c = ChunkRecord(id: "c\(i)", index: i, wallStart: 9 * 3600 + Double(i) * 30, fileOffset: Double(i) * 30, duration: 8,
                            peakDb: -20, meanDb: -30, audioFile: "", status: .stored, speechConfidence: 1, confirmedSeconds: 8)
        c.transcript = text; c.dayId = day; c.speakerId = speaker
        return c
    }

    @Test func promisesAreReadOutLoudInOneSentence() {
        let chunks = [chunk(0, "I will send you the API specification by Wednesday noon.", day: "2026-11-02"),
                      chunk(1, "The weather is lovely today.", day: "2026-11-02"),
                      chunk(2, "I'll call the plumber tomorrow morning.", day: "2026-11-02")]
        let said = IntentAnswers.promises(chunks: chunks, userName: "Levin", myVoice: nil, today: "2026-11-02")
        #expect(said.hasPrefix("You promised two things: "), "\(said)")
        #expect(said.contains("API specification") && said.contains("plumber"))
    }

    @Test func otherDaysAndOtherPeoplesPromisesAreLeftOut() {
        let chunks = [chunk(0, "I will send you the lease on Friday.", day: "2026-10-26"),
                      chunk(1, "I will bring the invoice tomorrow.", day: "2026-11-02", speaker: "voiceB")]
        #expect(IntentAnswers.promises(chunks: chunks, userName: "Levin", myVoice: "voiceA", today: "2026-11-02") == "You haven't promised anything today.")
        #expect(IntentAnswers.promises(chunks: [], userName: "Levin", myVoice: nil, today: "2026-11-02") == "I haven't heard anything today yet.")
    }

    @Test func promisesMarkedDoneAreNotRead() {
        let c = [chunk(0, "I will send you the API specification by Wednesday noon.", day: "2026-11-02")]
        let all = PromiseExtractor.extract(from: c, userName: "Levin")
        let said = IntentAnswers.promises(chunks: c, userName: "Levin", myVoice: nil, done: Set(all.map(\.id)), today: "2026-11-02")
        #expect(said == "You haven't promised anything today.")
    }

    @Test func forgettingIsReportedPlainly() {
        #expect(IntentAnswers.forgot(count: 0, minutes: 10) == "There was nothing from the last 10 minutes to forget.")
        #expect(IntentAnswers.forgot(count: 1, minutes: 5) == "Forgot 1 moment from the last 5 minutes.")
        #expect(IntentAnswers.forgot(count: 3, minutes: 30) == "Forgot 3 moments from the last 30 minutes.")
        #expect(IntentAnswers.clampMinutes(0) == 1 && IntentAnswers.clampMinutes(500) == 120 && IntentAnswers.clampMinutes(15) == 15)
    }

    @MainActor @Test func theRunningAppsModelsAnswerSiri() async {
        let hub = IntentHub()
        hub.ask = { q in WatchAnswer(text: "re: \(q)", source: .local, milliseconds: 1) }
        hub.forget = { $0 * 2 }
        hub.promises = { "none" }
        #expect(await hub.answer("hi").text == "re: hi")
        #expect(await hub.forgetRecent(minutes: 4) == 8)
        #expect(await hub.promisesToday() == "none")
    }
}
