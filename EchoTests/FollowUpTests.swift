import Foundation
import Testing
@testable import Echo

/// Records every request and answers with a fixed reply.
private final class RecordingMuse: MuseClient {
    var isStub = false
    var requests: [MuseRequest] = []
    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        requests.append(request)
        return MuseResponse(content: #"{"answer":"The spec is due first.","items":[],"follow_ups":[]}"#, model: "muse-spark-1.3", promptTokens: 1, completionTokens: 1, latencyMs: 1, isStub: false)
    }
}

struct FollowUpWordsTests {
    @Test func shortQuestionsThatLeanOnAnEarlierOneAreFollowUps() {
        for q in ["Which of those is due first?", "Who is it for?", "And what about Friday?", "What else did he say?", "Tell me more", "Why?",
                  "When does that happen?", "What did they decide?", "Which one is first?"] {
            #expect(FollowUp.isFollowUp(q), "\(q)")
        }
    }

    @Test func theDemoQuestionsAndOrdinaryQuestionsStandAlone() {
        for q in ["When is the plumber coming?", "What did Mister Brennan say about the lease?", "Where is Priya going in March?",
                  "What did I promise people today?", "Summarize my day", "What did I say this week?", "When is the first meeting?",
                  "What did Priya say to the landlord about the rent for next month and the deposit we discussed earlier?"] {
            #expect(!FollowUp.isFollowUp(q), "\(q)")
        }
    }

    @Test func combiningKeepsTheLastTwoSentencesOfTheEarlierText() {
        #expect(FollowUp.combine(previous: "What did I promise?", question: "Which is due first?") == "What did I promise? Which is due first?")
        let long = FollowUp.combine(previous: "One? Two? Three?", question: "Four?")
        #expect(long == "Two? Three? Four?", "a long chain doesn't grow without end")
    }
}

@MainActor
struct FollowUpAskTests {
    private struct Rig {
        let harness: Harness
        let ask: AskModel
        let ledger: LedgerModel
        let muse: RecordingMuse
        let clock: Clock
    }

    private final class Clock { var date = Date(timeIntervalSince1970: 1_700_000_000) }

    private func rig() async throws -> Rig {
        let h = try await Harness.make()
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-follow-\(UUID().uuidString)")!)
        ledger.cloudEnabled = true
        ledger.reviewBeforeSend = false
        let muse = RecordingMuse()
        let ask = AskModel(store: h.store, ledger: ledger, client: muse, model: "muse-spark-1.3")
        let clock = Clock()
        ask.now = { clock.date }
        return Rig(harness: h, ask: ask, ledger: ledger, muse: muse, clock: clock)
    }

    @Test func aFollowUpIsSentTogetherWithTheEarlierQuestionAndSaysSo() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        #expect(r.ask.followUpOf == nil)
        await r.ask.ask("Which of those is due first?")
        #expect(r.ask.followUpOf == "What did I promise people today?")
        let request = try #require(r.muse.requests.last)
        #expect(request.user.contains("What did I promise people today? Which of those is due first?"))
        #expect(request.developer.contains("short follow-up"))
        #expect(!(r.muse.requests.first?.developer.contains("short follow-up") ?? true), "an ordinary question's request is unchanged")
        #expect(r.muse.requests.count == 2)
        // what the person typed stays what is shown; the ledger records the text that was actually sent
        if case .cloudAnswered(let result) = r.ask.state { #expect(result.query == "Which of those is due first?") } else { Issue.record("expected a Muse answer") }
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.query == "What did I promise people today? Which of those is due first?")
        #expect(entry.reason.hasPrefix("Follow-up."))
    }

    @Test func theEarlierAnswerItselfIsNeverSent() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        await r.ask.ask("Which of those is due first?")
        let sent = r.muse.requests.map { $0.user + $0.developer }.joined()
        #expect(!sent.contains("The spec is due first."), "Muse's own earlier reply doesn't go back out")
    }

    @Test func askingOnItsOwnIgnoresTheEarlierQuestion() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        await r.ask.ask("Which of those is due first?", standalone: true)
        #expect(r.ask.followUpOf == nil)
        #expect(r.ledger.entries.first?.query == "Which of those is due first?")
    }

    @Test func aFollowUpAfterALongPauseStartsAFreshConversation() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        r.clock.date.addTimeInterval(FollowUp.memory + 1)
        await r.ask.ask("Which of those is due first?")
        #expect(r.ask.followUpOf == nil)
    }

    @Test func clearingStartsFresh() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        r.ask.clear()
        await r.ask.ask("Which of those is due first?")
        #expect(r.ask.followUpOf == nil)
    }

    @Test func retryingAFollowUpKeepsItsContext() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        await r.ask.ask("Which of those is due first?")
        await r.ask.ask("Which of those is due first?")   // the same words again, as a retry or "ask again"
        #expect(r.ask.followUpOf == "What did I promise people today?")
        #expect(r.ledger.entries.first?.query == "What did I promise people today? Which of those is due first?", "not doubled up")
    }
}
