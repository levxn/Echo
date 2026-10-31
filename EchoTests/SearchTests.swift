import Foundation
import Testing
@testable import Echo

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private struct FixtureChunk: Decodable {
    let id: String
    let index: Int
    let wallStart: Double
    let fileOffset: Double
    let duration: Double
    let peakDb: Double
    let meanDb: Double
    let audioFile: String
    let speechConfidence: Double
    let confirmedSeconds: Double
    let transcript: String
}

/// A store loaded from the real Day 1 transcripts, plus ground truth from the demo manifest.
@MainActor
struct Harness {
    let store: ChunkStore
    let retriever: Retriever
    let manifest: DemoManifest
    let chunks: [ChunkRecord]
    let directory: URL

    static func make() async throws -> Harness {
        let data = try Data(contentsOf: repoRoot.appending(path: "EchoTests/Fixtures/demo_transcripts.json"))
        let fixture = try JSONDecoder().decode([FixtureChunk].self, from: data)
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-search-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        var chunks: [ChunkRecord] = []
        for f in fixture {
            let record = ChunkRecord(id: f.id, index: f.index, wallStart: f.wallStart, fileOffset: f.fileOffset, duration: f.duration,
                                     peakDb: f.peakDb, meanDb: f.meanDb, audioFile: f.audioFile, status: .stored,
                                     speechConfidence: f.speechConfidence, confirmedSeconds: f.confirmedSeconds, transcript: f.transcript)
            chunks.append(record)
            await store.upsert(record)
            await store.index(id: f.id, normalizedText: TextNormalizer.normalized(f.transcript), embedding: Embedder.vector(for: f.transcript))
        }
        let manifest = try DemoManifest.load(from: repoRoot.appending(path: "Echo Watch App/Resources/demo_day.json"))
        return Harness(store: store, retriever: Retriever(store: store), manifest: manifest, chunks: chunks, directory: dir)
    }

    /// Chunks that overlap (by at least 40%) any of the given scripted lines (scene, line).
    func chunkIDs(forLines lines: [(Int, Int)]) -> Set<String> {
        var ids: Set<String> = []
        for (s, l) in lines {
            let line = manifest.scenes[s].lines[l]
            let length = line.end - line.start
            for c in chunks {
                let overlap = min(line.end, c.fileOffset + c.duration) - max(line.start, c.fileOffset)
                if overlap >= 0.4 * length { ids.insert(c.id) }
            }
        }
        return ids
    }

    /// Chunks belonging to a whole scene.
    func chunkIDs(forScene s: Int) -> Set<String> {
        chunkIDs(forLines: manifest.scenes[s].lines.indices.map { (s, $0) })
    }

    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor
struct SearchTests {
    private struct Case {
        let query: String
        let lines: [(Int, Int)]
        var scene: Int? = nil
    }

    private static let lookups: [Case] = [
        Case(query: "When is the plumber coming?", lines: [(2, 2), (2, 3)]),
        Case(query: "What did Mister Brennan say about the lease?", lines: [(2, 0), (2, 4), (2, 6), (2, 8)]),
        Case(query: "Where is Priya going in March?", lines: [(1, 0)]),
        Case(query: "What is the rent increase for the renewal?", lines: [(2, 6), (2, 7)]),
        Case(query: "When do I need to decide about the lease?", lines: [(2, 8), (2, 9)]),
        Case(query: "When is Mom's birthday?", lines: [(3, 2), (1, 6), (1, 7)]),
        Case(query: "What groceries do we need?", lines: [(3, 7)]),
        Case(query: "When do we deploy to production?", lines: [(0, 1)]),
        Case(query: "What is the risk with the payment provider?", lines: [(0, 5), (0, 6)]),
        Case(query: "Who should I call on Sunday?", lines: [(3, 5), (3, 6)]),
        Case(query: "What was said around 3pm?", lines: [], scene: 2),
        Case(query: "What happened in the evening?", lines: [], scene: 3),
    ]

    private static let broad = [
        "What did I promise people today?", "Summarize my day", "What should I do tomorrow?",
        "Give me a recap of everything", "List all my commitments", "What is the capital of France?",
    ]

    @Test func retrievalAndRoutingOnTheRealTranscripts() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        var report = "chunks indexed: \(h.chunks.count)\n\n"
        var top1 = 0, top3 = 0, routedLocal = 0
        var times: [Double] = []

        for c in Self.lookups {
            let expected = c.scene.map { h.chunkIDs(forScene: $0) } ?? h.chunkIDs(forLines: c.lines)
            let outcome = await h.retriever.search(c.query)
            let decision = Router.route(query: c.query, outcome: outcome)
            let ids = outcome.hits.map(\.chunk.id)
            let rank = ids.firstIndex { expected.contains($0) }.map { $0 + 1 }
            if rank == 1 { top1 += 1 }
            if let rank, rank <= 3 { top3 += 1 }
            if decision.tier == .local { routedLocal += 1 }
            times.append(outcome.elapsedMs)
            let answer = AnswerExtractor.extract(from: outcome)
            report += "Q: \(c.query)\n  first expected hit at rank: \(rank.map(String.init) ?? "none")   route: \(decision.tier.rawValue)   \(String(format: "%.1f", outcome.elapsedMs)) ms\n"
            report += "  known: \(outcome.knownTerms)  unknown: \(outcome.unknownTerms)  coverage: \(String(format: "%.2f", outcome.coverage))  window: \(outcome.timeWindow?.label ?? "-")\n"
            report += "  headline: \(answer?.headline ?? "-")\n"
            for hit in outcome.hits.prefix(3) {
                report += "    #\(hit.chunk.index) \(hit.chunk.wallLabel) \(expected.contains(hit.chunk.id) ? "✓" : " ") score \(String(format: "%.4f", hit.score)) \(hit.matchedTerms) \(hit.chunk.transcript ?? "")\n"
            }
            report += "\n"
        }

        var broadCloud = 0
        for q in Self.broad {
            let outcome = await h.retriever.search(q)
            let decision = Router.route(query: q, outcome: outcome)
            if decision.tier == .cloud { broadCloud += 1 }
            report += "Q: \(q)\n  route: \(decision.tier.rawValue) — \(decision.reason) \(decision.signals)\n\n"
        }

        let maxMs = times.max() ?? 0
        let medianMs = times.sorted()[times.count / 2]
        report = "SUMMARY top1 \(top1)/\(Self.lookups.count), top3 \(top3)/\(Self.lookups.count), routed local \(routedLocal)/\(Self.lookups.count), broad->cloud \(broadCloud)/\(Self.broad.count), median \(String(format: "%.1f", medianMs)) ms, slowest \(String(format: "%.1f", maxMs)) ms\n\n" + report
        try? report.write(toFile: "/tmp/echo_search_report.txt", atomically: true, encoding: .utf8)

        #expect(top3 >= 11, "top-3 \(top3)/\(Self.lookups.count)")
        #expect(top1 >= 8, "top-1 \(top1)/\(Self.lookups.count)")
        #expect(routedLocal == Self.lookups.count, "lookups routed local: \(routedLocal)/\(Self.lookups.count)")
        #expect(broadCloud == Self.broad.count, "broad queries routed to cloud: \(broadCloud)/\(Self.broad.count)")
        // Median, not max: the first search in a busy test process pays for loading the language model.
        #expect(medianMs < 250, "median search \(medianMs) ms (about 30 ms in the app once warmed up)")
    }

    @Test func queryParserFindsTimeAnchorsAndStripsThem() {
        let a = QueryParser.parse("What was said around 3pm?")
        let b0 = QueryParser.parse("What did we discuss at 3:30 pm about the lease")
        let c0 = QueryParser.parse("what happened in the evening")
        try? """
        a: window=\(String(describing: a.timeWindow)) tokens=\(a.contentTokens)
        b: window=\(String(describing: b0.timeWindow)) tokens=\(b0.contentTokens)
        c: window=\(String(describing: c0.timeWindow)) tokens=\(c0.contentTokens)
        """.write(toFile: "/tmp/echo_parser_report.txt", atomically: true, encoding: .utf8)
        #expect(a.timeWindow?.start == 15.0 * 3600 - 2700, "a window \(String(describing: a.timeWindow))")
        #expect(a.contentTokens.isEmpty, "a tokens \(a.contentTokens)")

        let b = QueryParser.parse("What did we discuss at 3:30 pm about the lease")
        #expect(b.timeWindow?.end == 15.5 * 3600 + 2700.0, "b window \(String(describing: b.timeWindow))")
        #expect(b.contentTokens == ["discuss", "lease"], "b tokens \(b.contentTokens)")

        let c = QueryParser.parse("what happened in the evening")
        #expect(c.timeWindow?.start == 17.0 * 3600, "c window \(String(describing: c.timeWindow))")
        #expect(c.contentTokens == ["happened"], "c tokens \(c.contentTokens)")

        #expect(QueryParser.parse("When is the plumber coming?").timeWindow == nil)
    }

    @Test func episodesGroupTheDayIntoItsFourConversations() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let episodes = EpisodeBuilder.build(from: h.chunks)
        let report = episodes.map { "\($0.startLabel)–\($0.endLabel) \($0.title) [\($0.chunks.count) moments] \($0.keywords) :: \($0.gist)" }.joined(separator: "\n")
        try? report.write(toFile: "/tmp/echo_episodes_report.txt", atomically: true, encoding: .utf8)

        #expect(episodes.map(\.startLabel) == ["09:05", "12:30", "15:10", "18:40"], "\(report)")
        #expect(episodes.map(\.title) == ["Morning conversation", "Midday conversation", "Afternoon conversation", "Evening conversation"])
        #expect(episodes.reduce(0) { $0 + $1.chunks.count } == h.chunks.count, "every stored moment belongs to a conversation")
        #expect(episodes.allSatisfy { $0.keywords.count == 3 && !$0.gist.isEmpty }, "\(report)")
    }
}


@MainActor
struct PlannerTests {
    private func decide(_ h: Harness, _ query: String) async -> (RetrievalOutcome, RouteDecision) {
        let outcome = await h.retriever.search(query)
        return (outcome, Router.route(query: query, outcome: outcome))
    }

    @Test func routerAssignsAnIntentToEveryQuestionKind() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let expectations: [(String, Tier, Intent)] = [
            ("What did I promise people today?", .cloud, .commitments),
            ("What should I do tomorrow?", .cloud, .commitments),
            ("List all my commitments", .cloud, .commitments),
            ("Summarize my day", .cloud, .summary),
            ("Give me a recap of everything", .cloud, .summary),
            ("What is the capital of France?", .cloud, .general),
            ("When is the plumber coming?", .local, .lookup),
            ("Where is Priya going in March?", .local, .lookup),
        ]
        for (query, tier, intent) in expectations {
            let (_, decision) = await decide(h, query)
            #expect(decision.tier == tier && decision.intent == intent, "\(query) -> \(decision.tier) / \(decision.intent)")
        }
    }

    @Test func commitmentsPlanSendsTheMomentsWithPromisesAndPlans() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let q = "What did I promise people today?"
        let (outcome, decision) = await decide(h, q)
        let plan = TierTwoPlanner.plan(query: q, decision: decision, outcome: outcome, chunks: h.chunks, model: "muse-spark-1.3")

        let promiseChunks = h.chunks.filter { ($0.transcript ?? "").lowercased().contains("promise") }
        #expect(promiseChunks.count >= 3)
        let sentTexts = Set(plan.snippets.map(\.text))
        for c in promiseChunks { #expect(sentTexts.contains(c.transcript ?? ""), "missing: \(c.transcript ?? "")") }
        #expect(plan.snippets.count >= 8 && plan.snippets.count <= TierTwoPlanner.commitmentCap + TierTwoPlanner.commitmentContextCap, "\(plan.snippets.count) snippets")
        // Each promise comes with the line spoken just before it, so Muse can tell who it was made to.
        let ordered = h.chunks.sorted { $0.wallStart < $1.wallStart }
        for (i, chunk) in ordered.enumerated() where i > 0 && ((chunk.transcript ?? "").lowercased().contains("promise")) {
            #expect(sentTexts.contains(ordered[i - 1].transcript ?? ""), "context line missing before: \(chunk.transcript ?? "")")
        }
        #expect(plan.snippets.map(\.time) == plan.snippets.map(\.time).sorted(), "snippets are in time order")
        #expect(plan.canCall && plan.textBytes > 0)

        let report = "commitments: \(plan.snippets.count) snippets, text \(plan.textBytes) B, body \(plan.bodyBytes) B\n" +
            plan.snippets.map { "\($0.time) — \($0.text)" }.joined(separator: "\n")
        try? report.write(toFile: "/tmp/echo_planner_report.txt", atomically: true, encoding: .utf8)
    }

    @Test func summaryPlanCoversTheWholeDayGroupedByConversation() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let q = "Summarize my day"
        let (outcome, decision) = await decide(h, q)
        let plan = TierTwoPlanner.plan(query: q, decision: decision, outcome: outcome, chunks: h.chunks, model: "muse-spark-1.3")
        #expect(plan.snippets.count == h.chunks.count)
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        #expect(body.components(separatedBy: "[Conversation starting").count - 1 == 4)
        #expect(plan.bodyBytes == (try plan.request.bodyData()).count && plan.bodyBytes < 20_000, "body \(plan.bodyBytes) B")
    }

    @Test func aQuestionThatMatchesNothingSendsNothing() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let q = "What is the capital of France?"
        let (outcome, decision) = await decide(h, q)
        let plan = TierTwoPlanner.plan(query: q, decision: decision, outcome: outcome, chunks: h.chunks, model: "muse-spark-1.3")
        #expect(!plan.canCall && plan.snippets.isEmpty, "sent \(plan.snippets.count) snippets")
    }

    @Test func theRequestCarriesTextOnlyAndNoLocalIdentifiers() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let q = "What did I promise people today?"
        let (outcome, decision) = await decide(h, q)
        let plan = TierTwoPlanner.plan(query: q, decision: decision, outcome: outcome, chunks: h.chunks, model: "muse-spark-1.3")
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        for chunk in h.chunks {
            #expect(!body.contains(chunk.id), "chunk id leaked")
            #expect(!body.contains(chunk.audioFile), "audio file name leaked")
        }
        #expect(!body.contains(".m4a") && !body.contains("\"audio\""))
        #expect(body.contains(q) && body.contains(" — "))
    }
}

/// A scriptable stand-in for the Muse API so the Ask flow can be tested without a network or a key.
private final class FakeMuse: MuseClient {
    var isStub = false
    var result: Result<String, MuseError> = .success(#"{"answer":"You made several promises.","items":[{"title":"Send the API spec","detail":"To Ravi","when":"Wednesday noon","source_time":"09:05"}]}"#)
    var delay: Duration = .zero
    private(set) var requests: [MuseRequest] = []

    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        requests.append(request)
        if delay > .zero { try await Task.sleep(for: delay) }
        switch result {
        case .success(let content):
            return MuseResponse(content: content, model: isStub ? "stub" : "muse-spark-1.3", promptTokens: 120, completionTokens: 30, latencyMs: 12, isStub: isStub)
        case .failure(let error): throw error
        }
    }
}

@MainActor
struct AskFlowTests {
    private struct Rig {
        let harness: Harness
        let ask: AskModel
        let ledger: LedgerModel
        let fake: FakeMuse
        let restoreSwitch: () -> Void
    }

    private func rig(cloudEnabled: Bool = true, configure: (FakeMuse) -> Void = { _ in }) async throws -> Rig {
        let h = try await Harness.make()
        // Isolated defaults: tests run in parallel and must not share (or leak) the cloud and review switches.
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-test-\(UUID().uuidString)")!)
        let previous: Any? = nil
        ledger.cloudEnabled = cloudEnabled
        let fake = FakeMuse()
        configure(fake)
        return Rig(harness: h, ask: AskModel(store: h.store, ledger: ledger, client: fake, model: "muse-spark-1.3"),
                   ledger: ledger, fake: fake,
                   restoreSwitch: {
                       if let previous { UserDefaults.standard.set(previous, forKey: "echo.cloudEnabled") }
                       else { UserDefaults.standard.removeObject(forKey: "echo.cloudEnabled") }
                       h.cleanup()
                   })
    }

    @Test func aLocalQuestionNeverCallsMuseAndIsLoggedAsStayingOnThePhone() async throws {
        let r = try await rig()
        defer { r.restoreSwitch() }
        await r.ask.ask("When is the plumber coming?")
        guard case .answered(let result) = r.ask.state else { Issue.record("expected a local answer"); return }
        #expect(result.note == nil && result.answer != nil)
        #expect(r.fake.requests.isEmpty)
        #expect(r.ledger.entries.count == 1 && r.ledger.entries[0].tier == .local)
        #expect(!r.ledger.entries[0].leftDevice && r.ledger.entries[0].bodyBytes == 0)
    }

    /// Waits (briefly) for the review sheet to be requested.
    private func waitForReview(_ ledger: LedgerModel) async throws -> ReviewGate.Pending {
        for _ in 0..<200 {
            if let pending = ledger.gate.pending { return pending }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the review was never requested")
        throw CancellationError()
    }

    @Test func withReviewOnNothingIsSentUntilTheUserApproves() async throws {
        let r = try await rig()
        defer { r.restoreSwitch() }
        r.ledger.reviewBeforeSend = true
        let task = Task { await r.ask.ask("What did I promise people today?") }
        let pending = try await waitForReview(r.ledger)
        #expect(pending.query == "What did I promise people today?" && pending.kind == .ask && pending.plan.snippets.count >= 8)
        #expect(r.fake.requests.isEmpty, "the request waits for approval")
        r.ledger.gate.approve()
        await task.value
        guard case .cloudAnswered = r.ask.state else { Issue.record("expected a cloud answer, got \(r.ask.state)"); return }
        #expect(r.fake.requests.count == 1, "approved once, sent once")
        #expect(r.ledger.gate.pending == nil)
    }

    @Test func decliningAtReviewSendsNothingAndIsLoggedAsHeldBack() async throws {
        let r = try await rig()
        defer { r.restoreSwitch() }
        r.ledger.reviewBeforeSend = true
        let task = Task { await r.ask.ask("What did I promise people today?") }
        _ = try await waitForReview(r.ledger)
        r.ledger.gate.cancel()
        await task.value
        guard case .answered(let result) = r.ask.state else { Issue.record("expected a held-back answer, got \(r.ask.state)"); return }
        #expect(result.note == .declined && result.answer != nil, "the closest local moments are still shown")
        #expect(r.fake.requests.isEmpty)
        let entry = try #require(r.ledger.entries.first)
        #expect(!entry.leftDevice && entry.bodyBytes == 0 && entry.reason == "You chose not to send this.")
        #expect(entry.snippets.count >= 8, "the ledger shows what would have been sent")
        #expect(LedgerTotals(r.ledger.entries).usedMuse == 0)
    }

    @Test func aNewQuestionDeclinesAReviewThatIsStillWaiting() async throws {
        let r = try await rig()
        defer { r.restoreSwitch() }
        r.ledger.reviewBeforeSend = true
        let first = Task { await r.ask.ask("What did I promise people today?") }
        _ = try await waitForReview(r.ledger)
        await r.ask.ask("When is the plumber coming?")   // answered locally, so it needs no review
        await first.value
        #expect(r.ledger.gate.pending == nil && r.fake.requests.isEmpty)
        guard case .answered(let result) = r.ask.state else { Issue.record("the newer local answer should win"); return }
        #expect(result.query == "When is the plumber coming?")
    }

    @Test func reviewDoesNotApplyToTheOfflineStub() async throws {
        let r = try await rig { $0.isStub = true }
        defer { r.restoreSwitch() }
        r.ledger.reviewBeforeSend = true
        await r.ask.ask("What did I promise people today?")
        guard case .cloudAnswered = r.ask.state else { Issue.record("a stub sends nothing, so it is not held for review"); return }
    }

    @Test func aCitationInTheReplyFindsItsMomentOnThePhone() async throws {
        let r = try await rig { $0.result = .success(#"{"answer":"One promise.","items":[{"title":"Second moment","detail":"d","when":"","source":"S2","source_time":"00:00"}],"follow_ups":["Next?"]}"#) }
        defer { r.restoreSwitch() }
        await r.ask.ask("What did I promise people today?")
        guard case .cloudAnswered(let result) = r.ask.state else { Issue.record("expected a cloud answer"); return }
        let item = try #require(result.answer.items.first)
        let found = try #require(CitationResolver.resolve(source: item.source, sourceTime: item.sourceTime, detail: item.detail,
                                                          snippets: result.plan.snippets, chunks: r.harness.chunks))
        #expect(found.id == result.plan.snippets[1].chunkID, "S2 is the second snippet of the request, whatever time the reply claims")
        #expect(result.answer.followUps == ["Next?"])
    }

    @Test func aBroadQuestionSendsOnlyTheChosenSnippetsAndLogsExactlyWhatLeft() async throws {
        let r = try await rig()
        defer { r.restoreSwitch() }
        await r.ask.ask("What did I promise people today?")
        guard case .cloudAnswered(let result) = r.ask.state else { Issue.record("expected a cloud answer, got \(r.ask.state)"); return }
        #expect(result.answer.items.first?.title == "Send the API spec")
        #expect(r.fake.requests.count == 1)

        let sent = String(decoding: try r.fake.requests[0].bodyData(), as: UTF8.self)
        #expect(!sent.contains("audio") && !sent.contains(".m4a"))

        let entry = try #require(r.ledger.entries.first)
        #expect(entry.tier == .cloud && entry.leftDevice && entry.status == .ok && !entry.isStub)
        #expect(entry.bodyBytes == (try r.fake.requests[0].bodyData()).count, "the ledger records the exact body size")
        #expect(entry.snippets == result.plan.snippets && entry.snippets.count >= 8)
        #expect(entry.promptTokens == 120 && entry.completionTokens == 30)
        #expect(LedgerTotals(r.ledger.entries).usedMuse == 1)
    }

    @Test func theCloudSwitchKeepsEverythingOnThePhone() async throws {
        let r = try await rig(cloudEnabled: false)
        defer { r.restoreSwitch() }
        await r.ask.ask("What did I promise people today?")
        guard case .answered(let result) = r.ask.state else { Issue.record("expected a held-back answer"); return }
        #expect(result.note == .cloudOff)
        #expect(r.fake.requests.isEmpty)
        let entry = try #require(r.ledger.entries.first)
        #expect(!entry.leftDevice && entry.bodyBytes == 0)
    }

    @Test func aQuestionWithNoRelevantMomentsSendsNothing() async throws {
        let r = try await rig()
        defer { r.restoreSwitch() }
        await r.ask.ask("What is the capital of France?")
        guard case .answered(let result) = r.ask.state else { Issue.record("expected nothing-matched"); return }
        #expect(result.note == .nothingMatched)
        #expect(r.fake.requests.isEmpty)
        #expect(LedgerTotals(r.ledger.entries).bytesSent == 0)
    }

    @Test func aFailedCallShowsTheErrorKeepsALocalFallbackAndRecordsWhatWasSent() async throws {
        let r = try await rig { $0.result = .failure(.rateLimited) }
        defer { r.restoreSwitch() }
        await r.ask.ask("What did I promise people today?")
        guard case .cloudFailed(let failure) = r.ask.state else { Issue.record("expected a failure"); return }
        #expect(failure.error == .rateLimited && failure.localAnswer != nil)
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.status == .error && entry.leftDevice && entry.bodyBytes > 0, "the request was transmitted before Meta refused it")
        #expect(!entry.error.isEmpty)

        r.fake.result = .success(#"{"answer":"Recovered.","items":[]}"#)
        await r.ask.retry()
        if case .cloudAnswered(let ok) = r.ask.state { #expect(ok.answer.answer == "Recovered.") } else { Issue.record("retry should succeed") }
    }

    @Test func anOfflineFailureRecordsThatNothingLeftThePhone() async throws {
        let r = try await rig { $0.result = .failure(.offline) }
        defer { r.restoreSwitch() }
        await r.ask.ask("Summarize my day")
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.status == .error && !entry.leftDevice && entry.bodyBytes == 0)
        #expect(LedgerTotals(r.ledger.entries).bytesSent == 0)
    }

    @Test func theStubIsLabeledAndSendsNothing() async throws {
        let r = try await rig { $0.isStub = true }
        defer { r.restoreSwitch() }
        await r.ask.ask("Summarize my day")
        guard case .cloudAnswered(let result) = r.ask.state else { Issue.record("expected a stub answer"); return }
        #expect(result.response.isStub)
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.isStub && !entry.leftDevice && entry.bodyBytes == 0 && entry.model == "stub")
        #expect(entry.snippets.count == r.harness.chunks.count, "it still records what would have been sent")
    }

    @Test func aNewerQuestionIsNotOverwrittenByASlowEarlierAnswer() async throws {
        let r = try await rig { $0.delay = .milliseconds(400) }
        defer { r.restoreSwitch() }
        let slow = Task { await r.ask.ask("Summarize my day") }
        try await Task.sleep(for: .milliseconds(100))
        await r.ask.ask("Where is Priya going in March?")
        await slow.value
        guard case .answered(let result) = r.ask.state else { Issue.record("the newer local answer should win, got \(r.ask.state)"); return }
        #expect(result.query == "Where is Priya going in March?")
        #expect(r.ledger.entries.count == 2, "both questions are still logged")
    }
}

@MainActor
struct DigestTests {
    private let digestJSON = """
    {"day_summary":"A busy day.","conversations":[{"time":"09:05","title":"Stand-up","summary":"Billing."}],
     "action_items":[{"what":"Send the API spec","to_whom":"Ravi","due":"Wednesday noon","source_time":"09:05"}],"people":["Ravi"]}
    """

    private func rig(cloudEnabled: Bool = true, configure: (FakeMuse) -> Void = { _ in }) async throws -> (DigestModel, LedgerModel, FakeMuse, Harness, () -> Void) {
        let h = try await Harness.make()
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-test-\(UUID().uuidString)")!)
        let previous = UserDefaults.standard.object(forKey: "echo.cloudEnabled")
        ledger.cloudEnabled = cloudEnabled
        let fake = FakeMuse()
        fake.result = .success(digestJSON)
        configure(fake)
        let digest = DigestModel(store: h.store, ledger: ledger, client: fake, model: "muse-spark-1.3")
        return (digest, ledger, fake, h, {
            if let previous { UserDefaults.standard.set(previous, forKey: "echo.cloudEnabled") }
            else { UserDefaults.standard.removeObject(forKey: "echo.cloudEnabled") }
            h.cleanup()
        })
    }

    @Test func aDigestIsRequestedStructuredSavedAndLogged() async throws {
        let (digest, ledger, fake, h, done) = try await rig()
        defer { done() }
        await digest.generate(chunks: h.chunks)
        guard case .ready(let ready) = digest.state else { Issue.record("expected a digest, got \(digest.state)"); return }
        #expect(ready.digest.actionItems.first?.what == "Send the API spec" && !ready.isStub)

        let request = try #require(fake.requests.first)
        #expect(request.schemaName == EchoSchemas.digestName)
        #expect(request.user.components(separatedBy: "[Conversation starting").count - 1 == 4, "the whole day, grouped by conversation")
        #expect(!(String(decoding: try request.bodyData(), as: UTF8.self)).contains("audio"))

        let entry = try #require(ledger.entries.first)
        #expect(entry.kind == .digest && entry.leftDevice && entry.snippets.count == h.chunks.count)

        // It survives a restart.
        let reloaded = DigestModel(store: h.store, ledger: ledger, client: fake, model: "muse-spark-1.3")
        await reloaded.load()
        if case .ready(let again) = reloaded.state { #expect(again.digest == ready.digest) } else { Issue.record("digest should reload") }
    }

    @Test func theCloudSwitchBlocksTheDigest() async throws {
        let (digest, _, fake, h, done) = try await rig(cloudEnabled: false)
        defer { done() }
        await digest.generate(chunks: h.chunks)
        if case .cloudOff = digest.state {} else { Issue.record("expected cloudOff, got \(digest.state)") }
        #expect(fake.requests.isEmpty)
    }

    @Test func anUnreadableReplyAndANetworkFailureAreBothReportedNotFaked() async throws {
        let (bad, _, _, h1, done1) = try await rig { $0.result = .success("not json at all") }
        defer { done1() }
        await bad.generate(chunks: h1.chunks)
        if case .failed = bad.state {} else { Issue.record("an unreadable digest must be a failure, got \(bad.state)") }

        let (offline, ledger, _, h2, done2) = try await rig { $0.result = .failure(.offline) }
        defer { done2() }
        await offline.generate(chunks: h2.chunks)
        if case .failed(let message) = offline.state { #expect(message.contains("internet")) } else { Issue.record("expected failure") }
        #expect(ledger.entries.first.map { !$0.leftDevice && $0.bodyBytes == 0 } == true)
        // And nothing was saved, so a relaunch doesn't show a digest that never existed.
        let fresh = DigestModel(store: h2.store, ledger: ledger, client: FakeMuse(), model: "muse-spark-1.3")
        await fresh.load()
        if case .idle = fresh.state {} else { Issue.record("no digest should be saved after a failure") }
    }
}
