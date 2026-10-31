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
private struct Harness {
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
        var maxMs = 0.0

        for c in Self.lookups {
            let expected = c.scene.map { h.chunkIDs(forScene: $0) } ?? h.chunkIDs(forLines: c.lines)
            let outcome = await h.retriever.search(c.query)
            let decision = Router.route(query: c.query, outcome: outcome)
            let ids = outcome.hits.map(\.chunk.id)
            let rank = ids.firstIndex { expected.contains($0) }.map { $0 + 1 }
            if rank == 1 { top1 += 1 }
            if let rank, rank <= 3 { top3 += 1 }
            if decision.tier == .local { routedLocal += 1 }
            maxMs = max(maxMs, outcome.elapsedMs)
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

        report = "SUMMARY top1 \(top1)/\(Self.lookups.count), top3 \(top3)/\(Self.lookups.count), routed local \(routedLocal)/\(Self.lookups.count), broad->cloud \(broadCloud)/\(Self.broad.count), slowest \(String(format: "%.1f", maxMs)) ms\n\n" + report
        try? report.write(toFile: "/tmp/echo_search_report.txt", atomically: true, encoding: .utf8)

        #expect(top3 >= 11, "top-3 \(top3)/\(Self.lookups.count)")
        #expect(top1 >= 8, "top-1 \(top1)/\(Self.lookups.count)")
        #expect(routedLocal == Self.lookups.count, "lookups routed local: \(routedLocal)/\(Self.lookups.count)")
        #expect(broadCloud == Self.broad.count, "broad queries routed to cloud: \(broadCloud)/\(Self.broad.count)")
        #expect(maxMs < 250, "slowest search \(maxMs) ms (about 30 ms when the machine is idle)")
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
        #expect(plan.snippets.count >= 8 && plan.snippets.count <= TierTwoPlanner.commitmentCap, "\(plan.snippets.count) snippets")
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
