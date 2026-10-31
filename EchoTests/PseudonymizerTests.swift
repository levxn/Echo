import Foundation
import Testing
@testable import Echo

@MainActor
struct PseudonymizerTests {
    private func masking(_ names: [String]) -> Masking {
        Masking(entries: names.enumerated().map { .init(original: $1, token: "[PERSON_\($0 + 1)]") })
    }

    // MARK: Masking and restoring text

    @Test func namesAreReplacedAsWholeWordsInAnyCase() {
        let m = masking(["Maya", "Priya"])
        #expect(m.mask("Maya asked priya about the Mayan ruins.") == "[PERSON_1] asked [PERSON_2] about the Mayan ruins.")
        #expect(m.mask("PRIYA's flight lands at noon") == "[PERSON_2]'s flight lands at noon", "a possessive keeps its 's")
    }

    @Test func aTitleStaysAndOnlyTheNameIsHidden() {
        #expect(masking(["Jordan", "Brennan"]).mask("Hello Jordan, this is Mr. Brennan") == "Hello [PERSON_1], this is Mr. [PERSON_2]")
    }

    @Test func aLongerNameIsMaskedBeforeAShorterOneInsideIt() {
        let m = masking(["Ann", "Anna"])
        #expect(m.mask("Anna met Ann") == "[PERSON_2] met [PERSON_1]")
    }

    @Test func restoringBringsTheNamesBackEvenIfTheModelChangedThePlaceholder() {
        let m = masking(["Priya", "Brennan"])
        #expect(m.restore("Send [PERSON_1] the link; [PERSON_2]'s lease ends soon.") == "Send Priya the link; Brennan's lease ends soon.")
        #expect(m.restore("person_1 and PERSON 2 and [person_2]") == "Priya and Brennan and Brennan")
        #expect(m.restore("[PERSON_9] is a stranger") == "[PERSON_9] is a stranger", "a number this request never used is left alone")
        #expect(Masking().restore("[PERSON_1]") == "[PERSON_1]", "nothing to restore when nothing was masked")
    }

    @Test func maskThenRestoreIsTheIdentity() {
        let m = masking(["Priya", "Jordan"])
        let text = "Thanks Priya, Jordan will call. Priya's sister is Jordan's friend."
        #expect(m.restore(m.mask(text)) == text)
    }

    // MARK: Finding the names in the demo day

    @Test func theDemoDaysPeopleAreFoundAndPlacesAreNot() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let m = Pseudonymizer.build(question: "What did I promise people today?", texts: h.chunks.map { $0.transcript ?? "" })
        let found = Set(m.entries.map(\.original))
        for name in ["Jordan", "Priya", "Brennan", "Patel"] { #expect(found.contains(name), "\(name) should be masked; found \(found)") }
        for word in ["Lisbon", "Thursday", "November", "API", "Mr", "Dr"] { #expect(!found.contains(word), "\(word) is not a person") }
        #expect(Set(m.entries.map(\.token)).count == m.count, "placeholders are distinct")
        #expect(m.entries.first?.token == "[PERSON_1]")
    }

    // MARK: What actually goes in the request

    private func plan(maskNames: Bool, _ h: Harness) async -> TierTwoPlan {
        let q = "What did I promise people today?"
        let outcome = await h.retriever.search(q)
        return TierTwoPlanner.plan(query: q, decision: Router.route(query: q, outcome: outcome), outcome: outcome,
                                   chunks: h.chunks, model: "muse-spark-1.3", maskNames: maskNames)
    }

    @Test func withMaskingOnNoNameIsInTheRequestAndTheDisclosureShowsTheSameText() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let plan = await plan(maskNames: true, h)
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        for name in ["Jordan", "Priya", "Brennan", "Patel"] {
            #expect(!body.contains(name), "\(name) leaked into the request")
            #expect(!plan.snippets.contains { $0.text.contains(name) }, "\(name) is in what the ledger would show")
        }
        #expect(plan.maskedCount >= 3 && body.contains("[PERSON_"))
        #expect(body.contains("placeholders like [PERSON_1]"), "the model is told how to treat them")
        for snippet in plan.snippets { #expect(body.contains(snippet.text), "what the UI shows is exactly what is sent: \(snippet.text)") }
    }

    @Test func withMaskingOffTheRequestIsUnchanged() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let plan = await plan(maskNames: false, h)
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        #expect(body.contains("Priya") && plan.masking.isEmpty && !body.contains("[PERSON_") && !body.contains("placeholders"))
    }

    @Test func theQuestionItselfIsMaskedToo() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let q = "What did I promise Priya today?"
        let outcome = await h.retriever.search(q)
        let plan = TierTwoPlanner.plan(query: q, decision: RouteDecision(tier: .cloud, reason: "", signals: [], intent: .commitments),
                                       outcome: outcome, chunks: h.chunks, model: "m", maskNames: true)
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        #expect(!body.contains("Priya") && body.contains("What did I promise [PERSON_"))
    }

    @Test func theDigestRequestIsMaskedAndStillLabelsEverySnippet() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let plan = TierTwoPlanner.digestPlan(chunks: h.chunks, model: "m", maskNames: true)
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        for name in ["Jordan", "Priya", "Brennan", "Patel"] { #expect(!body.contains(name), "\(name) leaked into the digest request") }
        for i in 1...plan.snippets.count { #expect(body.contains("S\(i) ")) }
        for snippet in plan.snippets { #expect(body.contains(snippet.text)) }
    }

    @Test func chunkIDsStillNeverLeakWhenMasking() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let body = String(decoding: try await plan(maskNames: true, h).request.bodyData(), as: UTF8.self)
        for chunk in h.chunks { #expect(!body.contains(chunk.id) && !body.contains(chunk.audioFile)) }
    }

    // MARK: Restoring what comes back

    @Test func aReplyIsRestoredBeforeItIsShownAndTheLedgerKeepsWhatCameBack() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-test-\(UUID().uuidString)")!)
        ledger.maskNames = true
        let fake = ScriptedMuse(content: #"{"answer":"You promised [PERSON_1] a reply.","items":[{"title":"Call [PERSON_1]","detail":"About [person_1]'s lease","when":"","source":"S1","source_time":"09:05"}],"follow_ups":["What did [PERSON_1] say?"]}"#)
        let ask = AskModel(store: h.store, ledger: ledger, client: fake, model: "m")
        await ask.ask("What did I promise people today?")
        guard case .cloudAnswered(let result) = ask.state else { Issue.record("expected a cloud answer, got \(ask.state)"); return }
        let first = try #require(result.plan.masking.entries.first).original
        #expect(result.answer.answer == "You promised \(first) a reply.")
        #expect(result.answer.items.first?.title == "Call \(first)" && result.answer.items.first?.detail == "About \(first)'s lease")
        #expect(result.answer.followUps == ["What did \(first) say?"])

        let entry = try #require(ledger.entries.first)
        #expect(entry.maskedNames == result.plan.maskedCount && entry.maskedNames >= 3)
        #expect(entry.response.contains("[PERSON_1]"), "the ledger keeps exactly what came back")
        #expect(!entry.snippets.contains { $0.text.contains("Priya") }, "and exactly the masked text that left")
        #expect(fake.requestBodies.count == 1 && !fake.requestBodies[0].contains("Priya"))
    }

    @Test func aDigestIsRestoredAndSavedRestoredSoARelaunchNeedsNoMapping() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-test-\(UUID().uuidString)")!)
        ledger.maskNames = true
        let json = #"{"day_summary":"A day with [PERSON_1].","conversations":[{"time":"09:05","title":"Chat with [PERSON_1]","summary":"s"}],"action_items":[{"what":"Email [PERSON_1]","to_whom":"[PERSON_1]","due":"Friday","source":"S2","source_time":"09:05"}],"people":["[PERSON_1]"]}"#
        let digest = DigestModel(store: h.store, ledger: ledger, client: ScriptedMuse(content: json), model: "m")
        await digest.generate(chunks: h.chunks)
        guard case .ready(let ready) = digest.state else { Issue.record("expected a digest, got \(digest.state)"); return }
        let first = try #require(TierTwoPlanner.digestPlan(chunks: h.chunks, model: "m", maskNames: true).masking.entries.first).original
        #expect(ready.digest.daySummary == "A day with \(first).")
        #expect(ready.digest.actionItems.first?.toWhom == first && ready.digest.people == [first])

        let reopened = DigestModel(store: h.store, ledger: ledger, client: ScriptedMuse(content: ""), model: "m")
        await reopened.load()
        guard case .ready(let again) = reopened.state else { Issue.record("the saved digest should load"); return }
        #expect(again.digest == ready.digest, "after a relaunch the names are already back")
    }

    @Test func withMaskingOffAReplyIsLeftExactlyAsItCame() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-test-\(UUID().uuidString)")!)
        ledger.maskNames = false
        let ask = AskModel(store: h.store, ledger: ledger, client: ScriptedMuse(content: #"{"answer":"[PERSON_1] stays literal.","items":[],"follow_ups":[]}"#), model: "m")
        await ask.ask("What did I promise people today?")
        guard case .cloudAnswered(let result) = ask.state else { Issue.record("expected a cloud answer"); return }
        #expect(result.answer.answer == "[PERSON_1] stays literal.")
        #expect(ledger.entries.first?.maskedNames == 0)
    }

    // MARK: Persistence

    @Test func theMaskedCountSurvivesTheLedgerStoreAndIsExported() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        var entry = LedgerEntry(query: "q", tier: .cloud)
        entry.maskedNames = 5
        entry.snippets = [Snippet(time: "09:05", text: "[PERSON_1] will call")]
        await h.store.upsertLedger(entry)
        let loaded = try #require(await h.store.ledgerEntries().first)
        #expect(loaded.maskedNames == 5)
        #expect(LedgerExport(entries: [loaded]).entries.first?.maskedNames == 5)
    }

    @Test func maskingIsOffUnlessTheUserTurnsItOnAndIsRemembered() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let defaults = UserDefaults(suiteName: "echo-mask-\(UUID().uuidString)")!
        let ledger = LedgerModel(store: h.store, defaults: defaults)
        #expect(ledger.maskNames == LedgerModel.maskNamesDefault)
        ledger.maskNames = !LedgerModel.maskNamesDefault
        #expect(LedgerModel(store: h.store, defaults: defaults).maskNames == !LedgerModel.maskNamesDefault)
    }
}

/// Replies with fixed content and remembers the request bodies it was sent.
private final class ScriptedMuse: MuseClient {
    var isStub: Bool { false }
    let content: String
    private(set) var requestBodies: [String] = []
    init(content: String) { self.content = content }

    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        requestBodies.append(String(decoding: try request.bodyData(), as: UTF8.self))
        return MuseResponse(content: content, model: "muse-spark-1.3", promptTokens: 100, completionTokens: 20, latencyMs: 5, isStub: false)
    }
}
