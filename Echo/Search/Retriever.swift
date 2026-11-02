import Foundation

struct Hit: Identifiable {
    let chunk: ChunkRecord
    let score: Double
    /// Query terms (normalized) that appear in this chunk.
    let matchedTerms: [String]
    let semantic: Float
    let inWindow: Bool
    var id: String { chunk.id }
}

struct RetrievalOutcome {
    let query: String
    /// Query terms that occur somewhere in the day's transcripts.
    let knownTerms: [String]
    /// Query terms that never occur (e.g. a name that was never said); ignored when judging confidence.
    let unknownTerms: [String]
    let timeWindow: TimeWindow?
    /// The days the question asked about, if it said ("last week"); nil means every day.
    var dayScope: DayScope? = nil
    let hits: [Hit]
    /// Rarity-weighted share of the known terms covered by the top three hits together.
    let coverage: Double
    /// Per-term weights for choosing the answer sentence: rare terms count more, names and titles less.
    let headlineWeights: [String: Double]
    let corpusSize: Int
    let elapsedMs: Double

    var timeAnchored: Bool { timeWindow != nil && hits.contains { $0.inWindow } }
}

/// Hybrid retrieval over the day's transcripts: SQLite FTS5 (BM25) and mean-centered cosine over averaged
/// word vectors, merged with reciprocal-rank fusion, plus a soft boost for chunks inside a time anchor.
struct Retriever {
    let store: ChunkStore
    /// Replaced in tests.
    var now: Date = Date()

    static let rrfK = 60.0
    static let keywordWeight = 1.0
    static let semanticWeight = 0.7
    static let semanticDepth = 10
    static let timeBoost = 0.02
    /// When several days are remembered, a newer one's match counts a little more: close scores go to the latest fact.
    static let recencyBoost = 0.03

    func search(_ query: String, limit: Int = 5) async -> RetrievalOutcome {
        let clock = ContinuousClock()
        let started = clock.now
        let parsed = QueryParser.parse(query, now: now)
        let corpus = await store.all().filter {
            $0.status == .stored && !($0.transcript ?? "").isEmpty && (parsed.dayScope?.contains($0.dayId) ?? true)
        }
        let byID = Dictionary(uniqueKeysWithValues: corpus.map { ($0.id, $0) })

        // Which chunks contain each query term, straight from FTS5 so matching agrees with ranking.
        var known: [String] = [], unknown: [String] = []
        var termChunks: [String: Set<String>] = [:]
        for token in parsed.contentTokens {
            let ids = Set(await store.ftsSearch(tokens: [token], limit: 200).map(\.id).filter { byID[$0] != nil })
            if ids.isEmpty { unknown.append(token) } else { known.append(token); termChunks[token] = ids }
        }

        // Keyword leg.
        let keyword = await store.ftsSearch(tokens: known, limit: 20).filter { byID[$0.id] != nil }

        // Semantic leg: uses every content word, including unknown ones, since a vector can bridge
        // vocabulary gaps ("plumber" ~ "repair").
        var semanticScores: [String: Float] = [:]
        var semantic: [(id: String, sim: Float)] = []
        let embeddings = await store.embeddings()
        if let q = Embedder.vector(for: parsed.contentTokens.joined(separator: " ")), !embeddings.isEmpty {
            let mean = Embedder.mean(of: Array(embeddings.values))
            semantic = corpus.compactMap { c in embeddings[c.id].map { (c.id, Embedder.centeredCosine(q, $0, mean: mean)) } }
                .sorted { $0.sim > $1.sim }
            semanticScores = Dictionary(uniqueKeysWithValues: semantic.map { ($0.id, $0.sim) })
        }

        var scores: [String: Double] = [:]
        for (rank, row) in keyword.enumerated() {
            scores[row.id, default: 0] += Self.keywordWeight / (Self.rrfK + Double(rank + 1))
        }
        for (rank, row) in semantic.prefix(Self.semanticDepth).enumerated() where row.sim > 0 {
            scores[row.id, default: 0] += Self.semanticWeight / (Self.rrfK + Double(rank + 1))
        }

        // Newer days win close calls.
        let dayOrder = Array(Set(corpus.map(\.dayId))).sorted()
        if dayOrder.count > 1 {
            let rank = Dictionary(uniqueKeysWithValues: dayOrder.enumerated().map { ($1, Double($0) / Double(dayOrder.count - 1)) })
            for id in scores.keys { if let c = byID[id] { scores[id]! *= 1 + Self.recencyBoost * (rank[c.dayId] ?? 1) } }
        }

        let window = parsed.timeWindow
        func inWindow(_ c: ChunkRecord) -> Bool { window?.overlaps(start: c.wallStart, duration: c.duration) ?? false }

        if let window {
            if scores.isEmpty {
                // Purely time-anchored question ("what happened around 3pm?"): everything in the window.
                for c in corpus where inWindow(c) { scores[c.id] = Self.timeBoost * (0.5 + 0.5 * window.closeness(of: c.wallStart)) }
            } else {
                for c in corpus where inWindow(c) && scores[c.id] != nil { scores[c.id]! += Self.timeBoost }
            }
        }

        let ranked = scores.sorted { a, b in
            a.value != b.value ? a.value > b.value
                : ((byID[a.key]?.dayId ?? "", byID[a.key]?.index ?? 0) < (byID[b.key]?.dayId ?? "", byID[b.key]?.index ?? 0))
        }.prefix(limit)

        let hits: [Hit] = ranked.compactMap { id, score in
            guard let chunk = byID[id] else { return nil }
            let matched = known.filter { termChunks[$0]?.contains(id) == true }
            return Hit(chunk: chunk, score: score, matchedTerms: matched, semantic: semanticScores[id] ?? 0, inWindow: inWindow(chunk))
        }

        // Rare terms (few chunks) say more than common ones, so weight each term by log(1 + N/df).
        func weight(_ t: String) -> Double { log(1 + Double(max(1, corpus.count)) / Double(max(1, termChunks[t]?.count ?? 1))) }
        let covered = Set(hits.prefix(3).flatMap(\.matchedTerms))
        let coverage: Double = known.isEmpty ? (parsed.contentTokens.isEmpty && !hits.isEmpty ? 1 : 0)
                                             : known.filter(covered.contains).reduce(0) { $0 + weight($1) } / known.reduce(0) { $0 + weight($1) }
        let names = TextNormalizer.nameTokens(in: query)
        var headlineWeights: [String: Double] = [:]
        for t in known {
            let factor = TextNormalizer.titles.contains(t) ? 0.1 : (names.contains(t) ? 0.3 : 1)
            headlineWeights[t] = weight(t) * factor
        }

        let elapsed = started.duration(to: clock.now)
        let ms = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15

        return RetrievalOutcome(query: query, knownTerms: known, unknownTerms: unknown, timeWindow: window, dayScope: parsed.dayScope,
                                hits: hits, coverage: coverage, headlineWeights: headlineWeights,
                                corpusSize: corpus.count, elapsedMs: ms)
    }
}
