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
        #expect(maxMs < 100, "slowest search \(maxMs) ms")
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
