import Foundation
import Testing
@testable import Echo

@MainActor
struct LedgerTests {
    private func makeStore() -> (ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-ledger-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ChunkStore(directory: dir), dir)
    }

    private func local(_ q: String) -> LedgerEntry {
        LedgerEntry(query: q, tier: .local, reason: "direct match")
    }

    private func cloud(_ q: String, bytes: Int, snippets: Int, status: LedgerEntry.Status = .ok, stub: Bool = false) -> LedgerEntry {
        var e = LedgerEntry(query: q, tier: .cloud, reason: "needs synthesis")
        e.model = stub ? "stub" : "muse-spark-1.3"
        e.isStub = stub
        e.leftDevice = !stub && bytes > 0    // a stub never reaches Meta, and a request with no bytes never left
        e.bodyBytes = stub ? 0 : bytes
        e.snippets = (0..<snippets).map { Snippet(time: "09:0\($0 % 10)", text: "snippet \($0)") }
        e.status = status
        return e
    }

    @Test func entriesRoundTripThroughSQLiteNewestFirst() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var first = cloud("What did I promise?", bytes: 3002, snippets: 3)
        first.timestamp = Date(timeIntervalSince1970: 1_000)
        first.response = #"{"answer":"x","items":[]}"#
        first.promptTokens = 410; first.completionTokens = 96; first.latencyMs = 2300
        var second = local("When is the plumber coming?")
        second.timestamp = Date(timeIntervalSince1970: 2_000)

        await store.upsertLedger(first)
        await store.upsertLedger(second)
        let loaded = await store.ledgerEntries()

        #expect(loaded.map(\.query) == ["When is the plumber coming?", "What did I promise?"])
        #expect(loaded[1] == first, "every field survives the round trip, including the exact snippets")
        #expect(loaded[1].snippets.map(\.text) == ["snippet 0", "snippet 1", "snippet 2"])
    }

    @Test func updatingAPendingEntryReplacesItInsteadOfDuplicating() async {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var entry = cloud("Summarize my day", bytes: 5000, snippets: 4, status: .pending)
        await store.upsertLedger(entry)
        entry.status = .ok
        entry.completionTokens = 120
        await store.upsertLedger(entry)
        let loaded = await store.ledgerEntries()
        #expect(loaded.count == 1 && loaded[0].status == .ok && loaded[0].completionTokens == 120)
    }

    @Test func totalsCountWhatStayedLocalAndWhatLeft() {
        let entries = [
            local("a"), local("b"), local("c"),
            cloud("d", bytes: 3000, snippets: 16),
            cloud("e", bytes: 5200, snippets: 48),
            cloud("f", bytes: 900, snippets: 2, stub: true),                // a stub never reached Meta, so it sent nothing
            cloud("g", bytes: 0, snippets: 8, status: .error),              // offline: nothing left the phone
        ]
        let totals = LedgerTotals(entries)
        #expect(totals.questions == 7)
        #expect(totals.stayedOnPhone == 5, "3 local answers, the stub, and the request that never left")
        #expect(totals.usedMuse == 2, "only successful, non-stub cloud calls count as using Muse")
        #expect(totals.bytesSent == 3000 + 5200, "only calls that were really transmitted count")
        #expect(totals.snippetsSent == 16 + 48, "stubs and requests that never left send no snippets")
    }

    @Test func clearingTheLedgerEmptiesIt() async {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = LedgerModel(store: store)
        model.record(local("a"))
        model.record(cloud("b", bytes: 100, snippets: 1))
        try? await Task.sleep(for: .milliseconds(200))
        await model.reload()
        #expect(model.entries.count == 2)
        await model.clear()
        #expect(model.entries.isEmpty)
        #expect(await store.ledgerEntries().isEmpty)
    }

    @Test func resettingTheDayClearsTheDigestButKeepsTheAuditTrail() async {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsertLedger(cloud("b", bytes: 100, snippets: 1))
        await store.saveDigest(json: #"{"day_summary":"x"}"#, model: "muse-spark-1.3", isStub: false)
        #expect(await store.loadDigest()?.model == "muse-spark-1.3")

        await store.reset()
        #expect(await store.loadDigest() == nil, "the digest describes chunks that no longer exist")
        #expect(await store.ledgerEntries().count == 1, "the ledger records what already left the phone, so it stays")
    }

    @Test func theCloudSwitchPersists() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = "echo.cloudEnabled"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { saved == nil ? UserDefaults.standard.removeObject(forKey: key) : UserDefaults.standard.set(saved, forKey: key) }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(LedgerModel(store: store).cloudEnabled, "on by default")
        let model = LedgerModel(store: store)
        model.cloudEnabled = false
        #expect(LedgerModel(store: store).cloudEnabled == false)
    }
}
