import Foundation
import Testing
@testable import Echo

private final class FakeBrain: LocalBrain {
    var isAvailable = true
    var result: Result<CloudAnswer, Error> = .success(CloudAnswer(answer: "You promised to send the API specification by Wednesday noon.",
        items: [CloudItem(title: "Send the spec", detail: "To Ravi", when: "Wednesday noon", sourceTime: "09:05", source: "S1")]))
    var calls: [(developer: String, user: String)] = []
    func answer(developer: String, user: String) async throws -> CloudAnswer {
        calls.append((developer, user))
        return try result.get()
    }
}

private final class CountingMuse: MuseClient {
    var isStub = false
    var calls = 0
    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        calls += 1
        return MuseResponse(content: #"{"answer":"From Muse.","items":[],"follow_ups":[]}"#, model: "muse-spark-1.3", promptTokens: 1, completionTokens: 1, latencyMs: 1, isStub: false)
    }
}

@MainActor
struct LocalBrainTests {
    private struct Rig { let harness: Harness; let ask: AskModel; let ledger: LedgerModel; let brain: FakeBrain; let muse: CountingMuse; let history: AskHistoryModel }

    private func rig(cloud: Bool = true, prefer: Bool = false) async throws -> Rig {
        let h = try await Harness.make()
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-brain-\(UUID().uuidString)")!)
        ledger.cloudEnabled = cloud; ledger.reviewBeforeSend = false
        let muse = CountingMuse(), brain = FakeBrain()
        let ask = AskModel(store: h.store, ledger: ledger, client: muse, model: "m")
        let history = AskHistoryModel(store: h.store)
        ask.history = history
        ask.brain = brain
        ask.preferOnDevice = { prefer }
        return Rig(harness: h, ask: ask, ledger: ledger, brain: brain, muse: muse, history: history)
    }

    @Test func whenPreferredAWholeDayQuestionIsAnsweredOnThePhoneAndNothingIsSent() async throws {
        let r = try await rig(prefer: true)
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        guard case .cloudAnswered(let result) = r.ask.state else { Issue.record("expected an answer, got \(r.ask.state)"); return }
        #expect(result.onDevice && result.answer.answer.contains("API specification") && result.decision.tier == .onDevice)
        #expect(r.muse.calls == 0 && r.brain.calls.count == 1, "Muse was never asked")
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.tier == .onDevice && !entry.leftDevice && entry.bodyBytes == 0 && entry.status == .ok && !entry.snippets.isEmpty)
        #expect(r.brain.calls[0].user.contains("S1 "), "it was given the same labelled snippets Muse would get")
        #expect(r.brain.calls[0].developer.contains("ONLY the transcript snippets"))
        let saved = try #require(r.history.items.first)
        #expect(saved.source == .local && saved.detail.items.count == 1)
    }

    @Test func withTheCloudSwitchedOffThePhonesModelAnswersInsteadOfAShrug() async throws {
        let r = try await rig(cloud: false, prefer: false)
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        guard case .cloudAnswered(let result) = r.ask.state else { Issue.record("expected an answer, got \(r.ask.state)"); return }
        #expect(result.onDevice && r.muse.calls == 0)
    }

    @Test func ifTheModelCannotRunTheUsualWayIsUsedAndItsRefusalIsNotShownAsAnAnswer() async throws {
        let cloudOn = try await rig(prefer: true)
        defer { cloudOn.harness.cleanup() }
        cloudOn.brain.result = .failure(LocalBrainError.unavailable)
        await cloudOn.ask.ask("What did I promise people today?")
        guard case .cloudAnswered(let result) = cloudOn.ask.state else { Issue.record("expected Muse's answer"); return }
        #expect(!result.onDevice && cloudOn.muse.calls == 1 && cloudOn.ledger.entries.first?.tier == .cloud)

        let cloudOff = try await rig(cloud: false)
        defer { cloudOff.harness.cleanup() }
        cloudOff.brain.result = .failure(LocalBrainError.empty)
        await cloudOff.ask.ask("What did I promise people today?")
        guard case .answered(let note) = cloudOff.ask.state else { Issue.record("expected the cloud-off note"); return }
        #expect(note.note == .cloudOff && cloudOff.muse.calls == 0)
    }

    @Test func aPhoneWithoutTheModelOrWithoutThePreferenceUsesMuseAsBefore() async throws {
        let none = try await rig(prefer: true)
        defer { none.harness.cleanup() }
        none.brain.isAvailable = false
        await none.ask.ask("What did I promise people today?")
        #expect(none.brain.calls.isEmpty && none.muse.calls == 1)
        let unpreferred = try await rig(prefer: false)
        defer { unpreferred.harness.cleanup() }
        await unpreferred.ask.ask("What did I promise people today?")
        #expect(unpreferred.brain.calls.isEmpty && unpreferred.muse.calls == 1, "with the cloud on and no preference, Muse answers")
    }

    @Test func lookupsAreStillAnsweredByTheRulesNotByAModel() async throws {
        let r = try await rig(prefer: true)
        defer { r.harness.cleanup() }
        await r.ask.ask("When is the plumber coming?")
        guard case .answered = r.ask.state else { Issue.record("expected the local lookup"); return }
        #expect(r.brain.calls.isEmpty && r.muse.calls == 0)
    }

    @Test func theWatchIsToldItCameFromThePhone() async throws {
        let r = try await rig(prefer: true)
        defer { r.harness.cleanup() }
        let reply = await r.ask.quickAnswer("What did I promise people today?")
        #expect(reply.source == .local && reply.text.contains("API specification"))
    }

    @Test func theSystemModelReportsItselfHonestlyAndNeverCrashesWhenItCannotRun() async {
        let brain = SystemLocalBrain()
        if brain.isAvailable {
            // Available, but the model's assets may not be installed (as in a simulator): asking must fail cleanly, not crash.
            _ = try? await brain.answer(developer: "Answer briefly.", user: "Question: hi")
        } else {
            await #expect(throws: LocalBrainError.self) { try await brain.answer(developer: "x", user: "y") }
        }
    }
}
