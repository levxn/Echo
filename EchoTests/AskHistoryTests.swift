import Foundation
import Testing
@testable import Echo

/// A Muse stand-in with a scripted reply.
private final class TestMuse: MuseClient {
    var isStub = false
    var result: Result<String, MuseError> = .success(#"{"answer":"You promised two things.","items":[{"title":"Send the spec","detail":"To Ravi","when":"Wednesday noon","source":"S2","source_time":"09:05"}],"follow_ups":[]}"#)
    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        switch result {
        case .success(let content): return MuseResponse(content: content, model: "muse-spark-1.3", promptTokens: 10, completionTokens: 5, latencyMs: 3, isStub: isStub)
        case .failure(let error): throw error
        }
    }
}

@MainActor
struct AskHistoryTests {
    private struct Rig {
        let harness: Harness
        let ask: AskModel
        let history: AskHistoryModel
        let ledger: LedgerModel
        let muse: TestMuse
    }

    private func rig(cloud: Bool = true, review: Bool = false) async throws -> Rig {
        let h = try await Harness.make()
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-hist-\(UUID().uuidString)")!)
        ledger.cloudEnabled = cloud
        ledger.reviewBeforeSend = review
        let muse = TestMuse()
        let ask = AskModel(store: h.store, ledger: ledger, client: muse, model: "muse-spark-1.3")
        let history = AskHistoryModel(store: h.store)
        ask.history = history
        return Rig(harness: h, ask: ask, history: history, ledger: ledger, muse: muse)
    }

    private func record(_ q: String, at t: Double = 0, via: AskVia = .typed) -> AskRecord {
        AskRecord(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + t), question: q, shortAnswer: "answer to \(q)", source: .local, via: via,
                  detail: AskDetail(kind: .local, headline: "answer to \(q)"))
    }

    // MARK: Store

    @Test func recordsAreKeptNewestFirstAndSurviveAReload() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = AskHistoryModel(store: h.store)
        await model.record(record("first", at: 0))
        await model.record(record("second", at: 10))
        await model.record(record("third", at: 20))
        #expect(model.items.map(\.question) == ["third", "second", "first"])
        let reopened = AskHistoryModel(store: h.store)
        await reopened.reload()
        #expect(reopened.items.map(\.question) == ["third", "second", "first"], "it is on disk, not just in memory")
    }

    @Test func aRecordKeepsEverythingNeededToReopenIt() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let detail = AskDetail(kind: .cloud, headline: "Two promises.",
                               items: [.init(title: "Send the spec", detail: "To Ravi", when: "Wednesday noon", sourceTime: "09:05", chunkID: "chunk-1")],
                               sourceChunkIDs: ["a", "b"], terms: ["spec"], note: nil)
        let original = AskRecord(id: "fixed", timestamp: Date(timeIntervalSince1970: 1_700_000_000), question: "What did I promise?",
                                 shortAnswer: "Two promises.", source: .muse, via: .watchVoice, detail: detail, milliseconds: 5_300)
        await h.store.upsertHistory(original)
        let stored = await h.store.history()
        let loaded = try #require(stored.first)
        #expect(loaded == original)
        #expect(loaded.detail.items.first?.chunkID == "chunk-1", "the citation can still play its audio")
    }

    @Test func historyIsCappedAndTheOldestDropOff() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = AskHistoryModel(store: h.store)
        for i in 0..<(AskHistoryModel.capacity + 5) { await model.record(record("q\(i)", at: Double(i))) }
        #expect(model.items.count == AskHistoryModel.capacity)
        #expect(model.items.first?.question == "q\(AskHistoryModel.capacity + 4)")
        #expect(!model.items.contains { $0.question == "q0" }, "the oldest were dropped")
        #expect((await h.store.history(limit: 500)).count == AskHistoryModel.capacity, "and on disk too")
    }

    @Test func oneRecordCanBeDeletedAndAllCanBeCleared() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = AskHistoryModel(store: h.store)
        let a = record("a", at: 0), b = record("b", at: 1)
        await model.record(a); await model.record(b)
        await model.delete(id: a.id)
        let afterDelete = await h.store.history()
        #expect(model.items.map(\.question) == ["b"] && afterDelete.map(\.question) == ["b"])
        await model.delete(id: "no-such-id")
        #expect(model.items.count == 1)
        await model.clear()
        let afterClear = await h.store.history()
        #expect(model.items.isEmpty && afterClear.isEmpty)
    }

    @Test func theWatchGetsTheLastEightInTheShortForm() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = AskHistoryModel(store: h.store)
        for i in 0..<12 { await model.record(record("q\(i)", at: Double(i), via: .watchVoice)) }
        let recent = model.recentForWatch()
        #expect(recent.count == 8 && recent.first?.question == "q11" && recent.last?.question == "q4")
        #expect(recent.allSatisfy { $0.via == .watchVoice })
    }

    @Test func theWatchShowsEachQuestionOnceWithItsLatestAnswerWhilePhoneKeepsEveryTime() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = AskHistoryModel(store: h.store)
        await model.record(record("What did I promise?", at: 0))
        await model.record(record("When is the plumber coming?", at: 10))
        await model.record(record("what did i promise?", at: 20, via: .watchVoice))
        let recent = model.recentForWatch()
        #expect(recent.map(\.question) == ["what did i promise?", "When is the plumber coming?"], "the later wording and time win")
        #expect(model.items.count == 3, "the phone's own list is untouched")
    }

    // MARK: Wiping and privacy

    @Test func startingANewDayOrForgettingTheDayClearsTheHistoryButNotTheSettings() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.history.record(record("kept?"))
        await r.harness.store.reset()   // what a new watch replay and Forget my day both do
        #expect((await r.harness.store.history()).isEmpty)

        await r.history.record(record("forget me"))
        let model = PipelineModel(store: r.harness.store, defaults: UserDefaults(suiteName: "echo-hist-\(UUID().uuidString)")!)
        let defaults = UserDefaults(suiteName: "echo-hist-\(UUID().uuidString)")!
        let chunksDirectory = await r.harness.store.chunksDirectory
        await DayWiper.forget(resetDay: { await model.reset() }, ask: r.ask, digest: DigestModel(store: r.harness.store, ledger: r.ledger, client: r.muse, model: "m"),
                              player: ChunkPlayer(directory: chunksDirectory), ledger: r.ledger, includeLedger: false, defaults: defaults)
        let remaining = await r.harness.store.history()
        #expect(r.history.items.isEmpty && remaining.isEmpty, "in memory and on disk")
    }

    @Test func forgettingTheDayRemovesMusesRepliesFromTheLedgerButKeepsWhatWasSent() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?")
        try await Task.sleep(for: .milliseconds(150))   // the ledger saves in the background
        await r.ledger.reload()
        let before = try #require(r.ledger.entries.first { $0.leftDevice })
        #expect(!before.response.isEmpty && !before.snippets.isEmpty)

        await r.ledger.redactResponses()

        let after = try #require(r.ledger.entries.first { $0.id == before.id })
        #expect(after.response.isEmpty, "the answer about the day is gone")
        #expect(after.snippets == before.snippets && after.bodyBytes == before.bodyBytes && after.query == before.query, "what was sent is still on record")
        let onDisk = await r.harness.store.ledgerEntries()
        let reloaded = try #require(onDisk.first { $0.id == before.id })
        #expect(reloaded.response.isEmpty && reloaded.snippets == before.snippets, "on disk as well")
    }

    @Test func historyIsNeverPartOfTheLedgerExport() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.history.record(record("a very private question"))
        await r.ask.ask("When is the plumber coming?")
        let json = String(decoding: try LedgerExport(entries: r.ledger.entries).jsonData(), as: UTF8.self)
        #expect(!json.contains("a very private question") && !json.contains("shortAnswer") && !json.contains("detail"))
    }

    // MARK: What the Ask flow records

    @Test func aLocalAnswerIsRecordedWithItsMoments() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("When is the plumber coming?", via: .voice)
        let saved = try #require(r.history.items.first)
        #expect(saved.question == "When is the plumber coming?" && saved.via == .voice && saved.source == .local)
        #expect(saved.detail.kind == .local && saved.detail.headline.lowercased().contains("friday") && !saved.detail.sourceChunkIDs.isEmpty)
        #expect(saved.shortAnswer.lowercased().contains("friday") && !saved.detail.terms.isEmpty)
        let onDisk = await r.harness.store.history()
        #expect(onDisk.first?.id == saved.id, "and it is on disk when ask() returns")
    }

    @Test func aMuseAnswerIsRecordedWithCitationsThatCanStillPlay() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("What did I promise people today?", via: .watchVoice)
        let saved = try #require(r.history.items.first)
        #expect(saved.source == .muse && saved.via == .watchVoice && saved.detail.kind == .cloud)
        #expect(saved.shortAnswer == "You promised two things." && saved.detail.headline == saved.shortAnswer)
        let item = try #require(saved.detail.items.first)
        let chunk = try #require(r.harness.chunks.first { $0.id == item.chunkID }, "S2 resolved to a real moment on this phone")
        #expect(!(chunk.transcript ?? "").isEmpty)
    }

    @Test func namesAreStoredRestoredNotAsPlaceholders() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        r.ledger.maskNames = true
        r.muse.result = .success(#"{"answer":"You promised [PERSON_1] a reply.","items":[],"follow_ups":[]}"#)
        await r.ask.ask("What did I promise people today?")
        let saved = try #require(r.history.items.first)
        #expect(!saved.shortAnswer.contains("[PERSON_") && !saved.detail.headline.contains("[PERSON_"))
    }

    @Test func everyKindOfNonAnswerIsRecordedWithItsReason() async throws {
        // Cloud off.
        var r = try await rig(cloud: false)
        await r.ask.ask("What did I promise people today?")
        var saved = try #require(r.history.items.first)
        #expect(saved.source == .none && saved.detail.kind == .note && saved.detail.note?.contains("Cloud is off") == true)
        r.harness.cleanup()

        // Nothing matched.
        r = try await rig()
        await r.ask.ask("What is the capital of France?")
        saved = try #require(r.history.items.first)
        #expect(saved.source == .none && saved.detail.note?.contains("Nothing matched") == true)
        r.harness.cleanup()

        // Muse failed: the closest local moment is kept as the answer.
        r = try await rig()
        r.muse.result = .failure(.offline)
        await r.ask.ask("What did I promise people today?")
        saved = try #require(r.history.items.first)
        #expect(saved.detail.kind == .note && saved.detail.note?.contains("couldn't answer") == true)
        #expect(saved.source == .local || saved.source == .none)
        r.harness.cleanup()
    }

    @Test func decliningAtReviewIsRecordedAsNotSent() async throws {
        let r = try await rig(review: true)
        defer { r.harness.cleanup() }
        let task = Task { await r.ask.ask("What did I promise people today?") }
        for _ in 0..<300 where r.ledger.gate.pending == nil { try await Task.sleep(for: .milliseconds(10)) }
        r.ledger.gate.cancel()
        await task.value
        let saved = try #require(r.history.items.first)
        #expect(saved.source == .none && saved.detail.note == "You chose not to send this.")
    }

    @Test func aSupersededQuestionIsNotRecordedAsAnswered() async throws {
        let r = try await rig()
        defer { r.harness.cleanup() }
        await r.ask.ask("When is the plumber coming?")
        await r.ask.ask("Where is Priya going in March?")
        #expect(r.history.items.map(\.question) == ["Where is Priya going in March?", "When is the plumber coming?"])
    }
}
