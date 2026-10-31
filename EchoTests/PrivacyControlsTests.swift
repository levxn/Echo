import Foundation
import Testing
@testable import Echo

@MainActor
struct PrivacyControlsTests {
    private func entry(_ query: String, tier: Tier = .cloud, left: Bool = true) -> LedgerEntry {
        var e = LedgerEntry(query: query, tier: tier, reason: "because")
        e.leftDevice = left
        e.bodyBytes = left ? 4_321 : 0
        e.model = "muse-spark-1.3"
        e.snippets = [Snippet(time: "09:05", text: "I will send the API specification")]
        e.response = #"{"answer":"PRIVATE REPLY ABOUT THE DAY"}"#
        e.promptTokens = 900; e.completionTokens = 120; e.latencyMs = 6_400
        return e
    }

    // MARK: Export

    @Test func theExportCarriesWhatWasSentAndNeverTheReplyOrAKey() throws {
        let export = LedgerExport(entries: [entry("What did I promise?"), entry("When is the plumber?", tier: .local, left: false)])
        let json = String(decoding: try export.jsonData(), as: UTF8.self)
        #expect(json.contains("I will send the API specification") && json.contains("\"leftDevice\" : true"))
        #expect(!json.contains("PRIVATE REPLY"), "Muse's reply describes the user's day and is not exported")
        #expect(!json.lowercased().contains("api_key") && !json.lowercased().contains("bearer"))
        #expect(json.contains("\"exportedAt\"") && json.contains("Audio is never sent"))
    }

    @Test func theExportRoundTripsAndKeepsEveryEntry() throws {
        let entries = [entry("one"), entry("two"), entry("three", tier: .local, left: false)]
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let back = try decoder.decode(LedgerExport.self, from: try LedgerExport(entries: entries).jsonData())
        #expect(back.entries.map(\.query) == ["one", "two", "three"])
        #expect(back.entries[0].bodyBytes == 4_321 && back.entries[2].leftDevice == false)
        #expect(back.entries[0].snippets.first?.time == "09:05")
    }

    @Test func theExportIsWrittenToADatedFile() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try LedgerExport(entries: [entry("q")], now: Date(timeIntervalSince1970: 1_793_500_000)).write(into: dir)
        #expect(url.lastPathComponent.hasPrefix("echo-ledger-20") && url.pathExtension == "json")
        #expect((try Data(contentsOf: url)).count > 100)
    }

    // MARK: Review gate

    private func plan() async throws -> TierTwoPlan {
        let h = try await Harness.make()
        defer { h.cleanup() }
        return TierTwoPlanner.digestPlan(chunks: h.chunks, model: "muse-spark-1.3")
    }

    @Test func approvingResumesTheWaiterExactlyOnce() async throws {
        let gate = ReviewGate()
        let p = try await plan()
        let task = Task { await gate.confirm(plan: p, query: "q", kind: .digest) }
        for _ in 0..<200 where gate.pending == nil { try await Task.sleep(for: .milliseconds(10)) }
        #expect(gate.pending?.kind == .digest)
        gate.approve()
        gate.approve()   // a second tap must be harmless
        gate.cancel()
        #expect(await task.value == true)
        #expect(gate.pending == nil)
    }

    @Test func aSecondRequestDeclinesTheFirst() async throws {
        let gate = ReviewGate()
        let p = try await plan()
        let first = Task { await gate.confirm(plan: p, query: "first", kind: .ask) }
        for _ in 0..<200 where gate.pending == nil { try await Task.sleep(for: .milliseconds(10)) }
        let second = Task { await gate.confirm(plan: p, query: "second", kind: .ask) }
        #expect(await first.value == false, "the superseded review is declined, not left hanging")
        for _ in 0..<200 where gate.pending?.query != "second" { try await Task.sleep(for: .milliseconds(10)) }
        gate.approve()
        #expect(await second.value == true)
    }

    @Test func reviewBeforeSendIsOffByDefaultAndRemembered() async throws {
        let defaults = UserDefaults(suiteName: "echo-review-\(UUID().uuidString)")!
        let h = try await Harness.make()
        defer { h.cleanup() }
        let ledger = LedgerModel(store: h.store, defaults: defaults)
        #expect(ledger.reviewBeforeSend == false)
        ledger.reviewBeforeSend = true
        #expect(LedgerModel(store: h.store, defaults: defaults).reviewBeforeSend == true)
    }

    // MARK: Forget my day

    @Test func forgettingTheDayWipesItButKeepsTheLedgerKeyAndSettings() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-test-\(UUID().uuidString)")!)
        let client = StubMuseClient()
        let ask = AskModel(store: h.store, ledger: ledger, client: client, model: "m")
        let digest = DigestModel(store: h.store, ledger: ledger, client: client, model: "m")
        let player = ChunkPlayer(directory: await h.store.chunksDirectory)
        let defaults = UserDefaults(suiteName: "echo-forget-\(UUID().uuidString)")!
        defaults.set("a\nb", forKey: DayWiper.promiseDoneKey)
        defaults.set(true, forKey: "echo.cloudEnabled")
        await h.store.upsertLedger(entry("kept"))   // record() saves in the background; write directly so reload sees it
        await ledger.reload()
        await ask.ask("When is the plumber coming?")
        #expect(!(await h.store.all()).isEmpty)

        await DayWiper.forget(resetDay: { await h.store.reset() }, ask: ask, digest: digest, player: player,
                              ledger: ledger, includeLedger: false, defaults: defaults)

        #expect((await h.store.all()).isEmpty, "every transcript is gone")
        #expect((await h.store.ftsSearch(tokens: ["plumber"], limit: 5)).isEmpty, "and the search index")
        #expect(defaults.object(forKey: DayWiper.promiseDoneKey) == nil, "checked-off commitments are forgotten")
        #expect(defaults.bool(forKey: "echo.cloudEnabled"), "settings stay")
        #expect(ledger.entries.contains { $0.query == "kept" }, "the ledger is the record of what left, so it stays")
        if case .idle = ask.state {} else { Issue.record("the answer on screen is cleared") }
        if case .idle = digest.state {} else { Issue.record("the digest is cleared") }
    }

    @Test func forgettingTheDayAndTheLedgerClearsBoth() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-test-\(UUID().uuidString)")!)
        let client = StubMuseClient()
        await h.store.upsertLedger(entry("gone soon"))
        await ledger.reload()
        #expect(ledger.entries.count == 1)
        let defaults = UserDefaults(suiteName: "echo-forget-\(UUID().uuidString)")!
        let chunksDirectory = await h.store.chunksDirectory
        await DayWiper.forget(resetDay: { await h.store.reset() },
                              ask: AskModel(store: h.store, ledger: ledger, client: client, model: "m"),
                              digest: DigestModel(store: h.store, ledger: ledger, client: client, model: "m"),
                              player: ChunkPlayer(directory: chunksDirectory), ledger: ledger, includeLedger: true, defaults: defaults)
        #expect(ledger.entries.isEmpty)
        #expect((await h.store.ledgerEntries()).isEmpty)
    }
}
