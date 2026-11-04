import Foundation
import Testing
@testable import Echo

private final class ScriptedMuse: MuseClient {
    var isStub = false
    var content = ""
    var requests: [MuseRequest] = []
    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        requests.append(request)
        return MuseResponse(content: content, model: "muse-spark-1.3", promptTokens: 5, completionTokens: 5, latencyMs: 2, isStub: isStub)
    }
}

private func said(_ id: String, _ text: String, at wall: Double) -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: .stored, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: DayID.today())
}

/// The secrets used throughout: none of these may appear in anything that is sent, shown in the ledger, or exported.
private let secrets = ["hunter2", "482913", "4111 1111 1111 1111", "9876543210", "ravi.k@example.com"]

private func body(_ plan: TierTwoPlan) -> String { String(decoding: (try? plan.request.bodyData()) ?? Data(), as: UTF8.self) }

struct ConfidentialRequestTests {
    private let chunks = [
        said("a", "Priya, my wifi password is hunter2 and the code is 482913.", at: 100),
        said("b", "Pay with 4111 1111 1111 1111. Call me on 9876543210 or write to ravi.k@example.com.", at: 130),
        said("c", "I will text you the link tomorrow, that's a promise.", at: 160),
    ]

    private func assertNoSecrets(in text: String, _ what: String) {
        for s in secrets { #expect(!text.contains(s), "\(what) contains \(s)") }
    }

    @Test func noRequestKindCarriesASecret() {
        let digest = TierTwoPlanner.digestPlan(chunks: chunks, model: "m")
        let journal = TierTwoPlanner.journalPlan(chunks: chunks, day: DayID.today(), model: "m")
        let promise = Promise(id: "c#0", chunkID: "c", kind: .commitment, timeLabel: "12:30", wallStart: 160,
                              sentence: "I will text you the link tomorrow, my password is hunter2.", toWhom: "Priya", due: "Tomorrow", context: nil)
        let draft = TierTwoPlanner.draftPlan(promise: promise, chunks: chunks, tone: .friendly, channel: .text, model: "m")
        for (name, plan) in [("digest", digest), ("journal", journal), ("draft", draft)] {
            assertNoSecrets(in: body(plan), "the \(name) request body")
            assertNoSecrets(in: plan.snippets.map(\.text).joined(separator: " "), "the \(name) snippets")
            #expect(plan.masking.hasSecrets, "the \(name) plan holds secrets back")
            #expect(body(plan).contains("[PASSWORD_1]") || name == "draft" && body(plan).contains("[PASSWORD_1]"), "\(name) shows placeholders")
            #expect(plan.request.developer.contains("Sensitive details"), "\(name) tells Muse how to treat the placeholders")
        }
        #expect(digest.heldBack[.password] == 1 && digest.heldBack[.phone] == 1 && digest.heldBack[.card] == 1 && digest.heldBack[.email] == 1)
    }

    @Test func itHappensWhateverTheNameMaskingSettingIs() {
        let off = TierTwoPlanner.digestPlan(chunks: chunks, model: "m", maskNames: false)
        let on = TierTwoPlanner.digestPlan(chunks: chunks, model: "m", maskNames: true)
        assertNoSecrets(in: body(off), "unmasked-names request")
        assertNoSecrets(in: body(on), "masked-names request")
        #expect(body(off).contains("Priya"), "names are allowed to go, as the person chose")
        #expect(!body(on).contains("Priya") && body(on).contains("[PERSON_"))
        #expect(off.masking.entries.isEmpty && on.masking.hasSecrets)
    }

    @Test func aRequestWithNothingConfidentialIsUntouched() {
        let plain = [said("c", "I will text you the link tomorrow, that's a promise.", at: 160)]
        let plan = TierTwoPlanner.digestPlan(chunks: plain, model: "m")
        #expect(!plan.masking.hasSecrets && plan.heldBackCount == 0 && !plan.request.developer.contains("Sensitive details"))
        #expect(plan.snippets.first?.text == "I will text you the link tomorrow, that's a promise.")
    }

    @Test func answersAndDigestsKeepSecretsAsPlaceholdersButDraftsGetThemBack() throws {
        let plan = TierTwoPlanner.digestPlan(chunks: chunks, model: "m")
        let masking = plan.masking
        let answer = CloudAnswer(answer: "Your password is [PASSWORD_1].", items: [CloudItem(title: "Use [PASSWORD_1]", detail: "", when: "", sourceTime: "09:00")], followUps: [])
        let shown = answer.restored(masking)
        #expect(shown.answer.contains("[PASSWORD_1]") && !shown.answer.contains("hunter2"), "an answer on screen never gets a secret back")
        #expect(shown.items[0].title.contains("[PASSWORD_1]"))
        let draft = MessageDraft(subject: "", body: "Hi, the wifi password is [PASSWORD_1] and call [PHONE_1].").restoredOnPhone(masking)
        #expect(draft.body == "Hi, the wifi password is hunter2 and call 9876543210.", "a draft on this phone is filled in")
        let plainRestore = MessageDraft(subject: "", body: "[PASSWORD_1]").restored(masking)
        #expect(plainRestore.body == "[PASSWORD_1]", "the ordinary restore path does not bring secrets back")
    }

    @MainActor
    private func rig() throws -> (ledger: LedgerModel, muse: ScriptedMuse, drafts: DraftModel, store: ChunkStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-conf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        let ledger = LedgerModel(store: store, defaults: UserDefaults(suiteName: "echo-conf-\(UUID().uuidString)")!)
        ledger.cloudEnabled = true; ledger.reviewBeforeSend = false
        let muse = ScriptedMuse()
        return (ledger, muse, DraftModel(ledger: ledger, client: muse), store, dir)
    }

    @MainActor @Test func aDraftIsFilledInOnThePhoneWhileTheLedgerAndTheRequestHoldNoSecret() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        // The request holds only this promise's moment and the line before it, so only what those two contain is held back.
        r.muse.content = #"{"subject":"","body":"Hi Priya, call me on [PHONE_1] or write to [EMAIL_1]. I will text you the link tomorrow."}"#
        let promise = Promise(id: "c#0", chunkID: "c", kind: .commitment, timeLabel: "12:30", wallStart: 160,
                              sentence: "I will text you the link tomorrow.", toWhom: "Priya", due: "Tomorrow", context: nil)
        await r.drafts.generate(for: promise, tone: .friendly, channel: .text, chunks: chunks)
        guard case .ready(let ready) = r.drafts.state else { Issue.record("expected a draft, got \(r.drafts.state)"); return }
        #expect(ready.draft.body.contains("9876543210") && ready.draft.body.contains("ravi.k@example.com"), "the draft on the phone has the real values")
        // what was sent
        let sent = try #require(r.muse.requests.first)
        assertNoSecrets(in: sent.user + sent.developer, "the request to Muse")
        // what the ledger holds, on screen and stored
        let entry = try #require(r.ledger.entries.first)
        assertNoSecrets(in: entry.snippets.map(\.text).joined() + entry.query + entry.response, "the ledger row")
        #expect(entry.heldBack["phone"] == 1 && entry.heldBack["email"] == 1 && entry.heldBack["card"] == 1 && entry.heldBackCount == 3)
        try await Task.sleep(for: .milliseconds(300))
        let reloaded = await r.store.ledgerEntries()
        #expect(reloaded.first?.heldBack == entry.heldBack, "the counts survive a restart")
        // and in an export
        let export = String(decoding: try LedgerExport(entries: reloaded).jsonData(), as: UTF8.self)
        assertNoSecrets(in: export, "the exported ledger")
    }

    @MainActor @Test func aSecretTypedIntoAQuestionIsNotKeptInTheLedgerEither() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.ledger.record(LedgerEntry(query: "What was my password hunter2 again?", tier: .local))
        #expect(r.ledger.entries.first?.query == "What was my password [PASSWORD_1] again?")
    }

    @Test func theDraftsOwnPromiseSentenceIsRedactedToo() {
        let promise = Promise(id: "c#0", chunkID: "c", kind: .commitment, timeLabel: "12:30", wallStart: 160,
                              sentence: "I will give you the pin 4821 tomorrow.", toWhom: "Priya", due: "Tomorrow", context: nil)
        let plan = TierTwoPlanner.draftPlan(promise: promise, chunks: chunks + [said("d", "I will give you the pin 4821 tomorrow.", at: 170)], tone: .brief, channel: .text, model: "m")
        #expect(!body(plan).contains("4821"))
    }
}
