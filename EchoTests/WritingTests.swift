import Foundation
import Testing
@testable import Echo

private final class ScriptedMuse: MuseClient {
    var isStub = false
    var content = #"{"subject":"","body":"Hi Priya, I will send the link tomorrow."}"#
    var error: MuseError?
    var requests: [MuseRequest] = []
    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        requests.append(request)
        if let error { throw error }
        return MuseResponse(content: content, model: "muse-spark-1.3", promptTokens: 5, completionTokens: 5, latencyMs: 2, isStub: isStub)
    }
}

private func said(_ id: String, _ text: String, at wall: Double, day: String = DayID.today()) -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: .stored, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day)
}

private func promiseIn(_ chunk: String) -> Promise {
    Promise(id: "\(chunk)#0", chunkID: chunk, kind: .commitment, timeLabel: "12:30", wallStart: 0,
            sentence: "I will text you the link tomorrow.", toWhom: "Priya", due: "Tomorrow", context: nil)
}

struct WritingTypesTests {
    @Test func aDraftIsReadFromPlainOrFencedJSONAndNeedsABody() {
        #expect(MessageDraft.parse(#"{"subject":"Hi","body":"Hello"}"#) == MessageDraft(subject: "Hi", body: "Hello"))
        #expect(MessageDraft.parse("```json\n{\"subject\":\"\",\"body\":\"Hello\"}\n```")?.body == "Hello")
        #expect(MessageDraft.parse(#"{"subject":"Hi","body":""}"#) == nil && MessageDraft.parse("not json") == nil)
        #expect(MessageDraft(subject: "", body: "Hello").text == "Hello")
        #expect(MessageDraft(subject: "About the link", body: "Hello").text == "Subject: About the link\n\nHello")
    }

    @Test func namesComeBackIntoWhatMuseWrote() {
        let masking = Masking(entries: [.init(original: "Priya", token: "[PERSON_1]")])
        let d = MessageDraft(subject: "For [PERSON_1]", body: "Hi [PERSON_1], link tomorrow.").restored(masking)
        #expect(d.subject == "For Priya" && d.body == "Hi Priya, link tomorrow.")
        let e = JournalEntry(title: "A day with [PERSON_1]", entry: "I saw [PERSON_1].", highlights: ["Lunch with [PERSON_1]"]).restored(masking)
        #expect(e.title == "A day with Priya" && e.entry == "I saw Priya." && e.highlights == ["Lunch with Priya"])
    }

    @Test func aJournalEntryIsReadAndTextIncludesItsHighlights() {
        let e = JournalEntry.parse(#"{"title":"T","entry":"E","highlights":["a","b"]}"#)
        #expect(e == JournalEntry(title: "T", entry: "E", highlights: ["a", "b"]))
        #expect(e?.text == "T\n\nE\n\nHighlights\n• a\n• b")
        #expect(JournalEntry(title: "T", entry: "E", highlights: []).text == "T\n\nE")
        #expect(JournalEntry.parse(#"{"title":"T","entry":"","highlights":[]}"#) == nil)
    }

    @Test func theStubWritesBothSoNoKeyStillShowsTheFeature() async throws {
        let stub = StubMuseClient()
        for (schema, name) in [(EchoSchemas.draft, EchoSchemas.draftName), (EchoSchemas.journal, EchoSchemas.journalName)] {
            let response = try await stub.complete(MuseRequest(model: "m", developer: "", user: "x", schemaName: name, schemaJSON: schema))
            #expect(response.isStub)
            #expect(name == EchoSchemas.draftName ? MessageDraft.parse(response.content) != nil : JournalEntry.parse(response.content) != nil)
        }
    }
}

struct WritingPlanTests {
    private let chunks = [said("before", "Which hotel did you pick? A small place near the Alma district.", at: 90),
                          said("promise", "That sounds amazing Priya. I will text you the link tomorrow.", at: 100),
                          said("after", "Thanks, bye for now.", at: 110),
                          said("unrelated", "The landlord called about the lease.", at: 500),
                          said("lastweek", "I will text you the link tomorrow.", at: 100, day: "2020-01-01")]

    @Test func onlyThePromisesMomentAndTheLineBeforeItAreSent() {
        let plan = TierTwoPlanner.draftPlan(promise: promiseIn("promise"), chunks: chunks, tone: .friendly, channel: .text, model: "m")
        #expect(plan.snippets.map(\.chunkID) == ["before", "promise"])
        #expect(plan.request.schemaName == EchoSchemas.draftName && plan.canCall)
        let body = String(decoding: (try? plan.request.bodyData()) ?? Data(), as: UTF8.self)
        #expect(!body.contains("landlord") && !body.contains("bye for now"), "nothing else from the day leaves")
        #expect(body.contains("warm and friendly") && body.contains("text message") && body.contains("I will text you the link"))
    }

    @Test func aMomentFarFromThePromiseIsNotContext() {
        let far = [said("early", "Something said long before.", at: 10), said("promise", "I will text you the link tomorrow.", at: 300)]
        let plan = TierTwoPlanner.draftPlan(promise: promiseIn("promise"), chunks: far, tone: .brief, channel: .email, model: "m")
        #expect(plan.snippets.map(\.chunkID) == ["promise"])
        #expect(String(decoding: (try? plan.request.bodyData()) ?? Data(), as: UTF8.self).contains("email"))
    }

    @Test func aMissingMomentSendsNothing() {
        let plan = TierTwoPlanner.draftPlan(promise: promiseIn("gone"), chunks: chunks, tone: .formal, channel: .text, model: "m")
        #expect(!plan.canCall && plan.snippets.isEmpty)
    }

    @Test func namesCanBeMaskedInADraftRequest() {
        let plan = TierTwoPlanner.draftPlan(promise: promiseIn("promise"), chunks: chunks, tone: .friendly, channel: .text, model: "m", maskNames: true)
        let body = String(decoding: (try? plan.request.bodyData()) ?? Data(), as: UTF8.self)
        #expect(!body.contains("Priya") && body.contains("[PERSON_"))
    }

    @Test func theJournalIsTheWholeOfOneDayOnly() {
        let plan = TierTwoPlanner.journalPlan(chunks: chunks, day: DayID.today(), model: "m")
        #expect(Set(plan.snippets.map(\.chunkID)) == ["before", "promise", "after", "unrelated"] && plan.request.schemaName == EchoSchemas.journalName)
        let old = TierTwoPlanner.journalPlan(chunks: chunks, day: "2020-01-01", model: "m")
        #expect(old.snippets.map(\.chunkID) == ["lastweek"])
    }
}

@MainActor
struct WritingModelTests {
    private struct Rig {
        let ledger: LedgerModel
        let muse: ScriptedMuse
        let drafts: DraftModel
        let journal: JournalModel
        let store: ChunkStore
        let dir: URL
    }

    private func rig(cloud: Bool = true, review: Bool = false, mask: Bool = false) throws -> Rig {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-write-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        let ledger = LedgerModel(store: store, defaults: UserDefaults(suiteName: "echo-write-\(UUID().uuidString)")!)
        ledger.cloudEnabled = cloud; ledger.reviewBeforeSend = review; ledger.maskNames = mask
        let muse = ScriptedMuse()
        return Rig(ledger: ledger, muse: muse, drafts: DraftModel(ledger: ledger, client: muse), journal: JournalModel(store: store, ledger: ledger, client: muse),
                   store: store, dir: dir)
    }

    private let day = [said("before", "Which hotel did you pick?", at: 90), said("promise", "That sounds amazing Priya. I will text you the link tomorrow.", at: 100)]

    @Test func aDraftIsWrittenAndTheLedgerShowsExactlyWhatWasSent() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        await r.drafts.generate(for: promiseIn("promise"), tone: .friendly, channel: .text, chunks: day)
        guard case .ready(let ready) = r.drafts.state else { Issue.record("expected a draft, got \(r.drafts.state)"); return }
        #expect(ready.draft.body.contains("link tomorrow") && !ready.isStub)
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.kind == .draft && entry.snippets.count == 2 && entry.leftDevice && entry.status == .ok && entry.bodyBytes > 0)
        #expect(entry.query.contains("text message") && entry.query.contains("I will text you the link"))
    }

    @Test func theCloudSwitchAndAMissingMomentAreRespected() async throws {
        let off = try rig(cloud: false)
        defer { try? FileManager.default.removeItem(at: off.dir) }
        await off.drafts.generate(for: promiseIn("promise"), tone: .brief, channel: .text, chunks: day)
        guard case .cloudOff = off.drafts.state else { Issue.record("expected cloudOff"); return }
        #expect(off.muse.requests.isEmpty && off.ledger.entries.isEmpty, "nothing was sent or recorded")
        let on = try rig()
        defer { try? FileManager.default.removeItem(at: on.dir) }
        await on.drafts.generate(for: promiseIn("gone"), tone: .brief, channel: .text, chunks: day)
        guard case .failed = on.drafts.state else { Issue.record("expected a failure"); return }
        #expect(on.muse.requests.isEmpty)
    }

    @Test func decliningTheReviewSendsNothingAndIsRecorded() async throws {
        let r = try rig(review: true)
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let task = Task { await r.drafts.generate(for: promiseIn("promise"), tone: .friendly, channel: .text, chunks: day) }
        for _ in 0..<100 where r.ledger.gate.pending == nil { try await Task.sleep(for: .milliseconds(20)) }
        let pending = try #require(r.ledger.gate.pending)
        #expect(pending.kind == .draft && pending.plan.snippets.count == 2)
        r.ledger.gate.cancel()
        await task.value
        #expect(r.muse.requests.isEmpty)
        guard case .idle = r.drafts.state else { Issue.record("expected idle"); return }
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.kind == .draft && !entry.leftDevice && entry.reason == "You chose not to send this.")
    }

    @Test func approvingTheReviewSendsIt() async throws {
        let r = try rig(review: true)
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let task = Task { await r.drafts.generate(for: promiseIn("promise"), tone: .friendly, channel: .text, chunks: day) }
        for _ in 0..<100 where r.ledger.gate.pending == nil { try await Task.sleep(for: .milliseconds(20)) }
        r.ledger.gate.approve()
        await task.value
        #expect(r.muse.requests.count == 1)
        guard case .ready = r.drafts.state else { Issue.record("expected a draft"); return }
    }

    @Test func aFailureAndAnUnreadableReplyAreExplained() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.muse.error = .timedOut
        await r.drafts.generate(for: promiseIn("promise"), tone: .friendly, channel: .text, chunks: day)
        guard case .failed = r.drafts.state else { Issue.record("expected failed"); return }
        r.muse.error = nil; r.muse.content = "I can't help with that."
        await r.drafts.generate(for: promiseIn("promise"), tone: .friendly, channel: .text, chunks: day)
        guard case .failed(let message) = r.drafts.state else { Issue.record("expected failed"); return }
        #expect(message.contains("couldn't be read"))
    }

    @Test func maskedNamesAreRestoredInTheDraftButNeverSent() async throws {
        let r = try rig(mask: true)
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.muse.content = #"{"subject":"","body":"Hi [PERSON_1], I will text you the link tomorrow."}"#
        await r.drafts.generate(for: promiseIn("promise"), tone: .friendly, channel: .text, chunks: day)
        let sent = String(decoding: (try? r.muse.requests[0].bodyData()) ?? Data(), as: UTF8.self)
        #expect(!sent.contains("Priya"))
        guard case .ready(let ready) = r.drafts.state else { Issue.record("expected a draft"); return }
        #expect(ready.draft.body.hasPrefix("Hi Priya,"))
    }

    @Test func theJournalIsWrittenSavedAndComesBackAfterARelaunch() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.muse.content = #"{"title":"A full day","entry":"I promised the link.","highlights":["Lunch with Priya"]}"#
        await r.journal.generate(chunks: day)
        guard case .ready(let ready) = r.journal.state else { Issue.record("expected an entry"); return }
        #expect(ready.entry.title == "A full day" && ready.day == DayID.today())
        #expect(r.ledger.entries.first?.kind == .journal)
        let reopened = JournalModel(store: r.store, ledger: r.ledger, client: r.muse)
        await reopened.load()
        guard case .ready(let again) = reopened.state else { Issue.record("expected it back"); return }
        #expect(again.entry == ready.entry)
    }

    @Test func otherDaysEntriesAreListedSeparatelyAndForgettingADayForgetsItsEntry() async throws {
        let r = try rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let json = #"{"title":"Old","entry":"An old day.","highlights":[]}"#
        await r.store.saveJournal(json: json, model: "m", isStub: false, day: "2026-10-26")
        await r.store.saveJournal(json: json, model: "m", isStub: false, day: DayID.today())
        let m = JournalModel(store: r.store, ledger: r.ledger, client: r.muse)
        await m.load()
        #expect(m.earlier.map(\.day) == ["2026-10-26"])
        await r.store.upsert(said("x", "something", at: 1, day: "2026-10-26"))
        await r.store.deleteDay("2026-10-26")
        let left = await r.store.journals().map(\.day)
        #expect(left == [DayID.today()])
    }

    @Test func theEveningNudgeIsTheNextNineAndSaysNothingAboutTheDay() async {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let afternoon = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 15))!
        let night = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 22))!
        #expect(JournalReminder.fireDate(now: afternoon, calendar: cal) == cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 21)))
        #expect(JournalReminder.fireDate(now: night, calendar: cal) == cal.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 21)))
        final class Fake: NotificationScheduling {
            var added: [(id: String, body: String)] = []
            var removed: [String] = []
            func ensureAuthorized() async -> Bool { true }
            func add(id: String, title: String, body: String, at date: Date) async throws { added.append((id, body)) }
            func remove(ids: [String]) { removed += ids }
        }
        let fake = Fake()
        let r = await MainActor.run { Reminders(scheduler: fake, defaults: UserDefaults(suiteName: "echo-evening-\(UUID().uuidString)")!, now: { Date() }) }
        await r.setEveningJournal(enabled: true)
        #expect(fake.added.count == 1 && fake.added[0].id == JournalReminder.notificationID && !fake.added[0].body.lowercased().contains("promise"))
        await r.setEveningJournal(enabled: false)
        #expect(fake.added.count == 1 && fake.removed.count == 2, "turning it off removes it")
    }
}
