import Foundation
import Testing
@testable import Echo

@MainActor
struct WatchAskTests {
    @Test func theAnswerSurvivesTheWireFormat() throws {
        let answer = WatchAnswer(text: "Friday at 10 in the morning.", source: .local, milliseconds: 412)
        let back = try #require(WatchAnswer(dictionary: answer.dictionary))
        #expect(back == answer)
        #expect(WatchAnswer(dictionary: [Wire.okKey: false]) == nil, "a refusal is not an answer")
        #expect(WatchAnswer(dictionary: [:]) == nil)
        let odd = try #require(WatchAnswer(dictionary: [Wire.okKey: true, Wire.answerKey: "x", Wire.tierKey: "martian"]))
        #expect(odd.source == .none, "an unknown source is shown as no source, not trusted")
    }

    @Test func aLongAnswerIsCutAtASentenceNotMidWord() {
        let long = "You promised to send the spec by Wednesday noon. You will also review the design document on Tuesday. "
            + String(repeating: "Then there are many other smaller errands and chores that fill the rest of the week. ", count: 6)
        let brief = WatchAnswer.brief(long)
        #expect(brief.count <= 220 && brief.hasSuffix("."))
        #expect(brief.hasPrefix("You promised to send the spec by Wednesday noon."))
        #expect(WatchAnswer.brief("Short one.") == "Short one.")
        let oneRun = WatchAnswer.brief(String(repeating: "word ", count: 120))
        #expect(oneRun.count <= 221 && oneRun.hasSuffix("…"), "a single endless sentence is cut at a word")
    }

    @Test func thePresetsAreDistinctAndEachOneRoutesTheWayItClaims() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        #expect(Set(QuickAsk.presets.map(\.question)).count == QuickAsk.presets.count)
        #expect(QuickAsk.presets.contains { $0.usesCloud } && QuickAsk.presets.contains { !$0.usesCloud })
        for preset in QuickAsk.presets {
            let outcome = await h.retriever.search(preset.question)
            let decision = Router.route(query: preset.question, outcome: outcome)
            #expect((decision.tier == .cloud) == preset.usesCloud, "\"\(preset.question)\" routes to \(decision.tier), preset says cloud=\(preset.usesCloud)")
        }
    }
}
