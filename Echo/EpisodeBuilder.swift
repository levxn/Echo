import Foundation

/// A conversation: a run of moments with no long gap between them.
struct Episode: Identifiable {
    let id: Int
    let start: Double          // seconds since midnight
    let end: Double
    let chunks: [ChunkRecord]
    let title: String          // "Morning conversation"
    let gist: String           // the most representative sentence
    let keywords: [String]

    var startLabel: String { DemoClock.format(start) }
    var endLabel: String { DemoClock.format(end) }
    var minutes: Int { max(1, Int(((end - start) / 60).rounded())) }
}

/// Groups the day's stored moments into conversations and summarizes each one without a model:
/// keywords by TF-IDF across conversations, gist by the highest-scoring sentence.
enum EpisodeBuilder {
    /// A silence longer than this starts a new conversation.
    static let gapSeconds = 600.0

    static func build(from chunks: [ChunkRecord], gap: Double = gapSeconds) -> [Episode] {
        let stored = chunks
            .filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }
            .sorted { ($0.dayId, $0.wallStart) < ($1.dayId, $1.wallStart) }
        guard !stored.isEmpty else { return [] }

        // A conversation never spans two days, however close their clock times are.
        var groups: [[ChunkRecord]] = [[stored[0]]]
        for chunk in stored.dropFirst() {
            let previous = groups[groups.count - 1].last!
            if chunk.dayId != previous.dayId || chunk.wallStart - (previous.wallStart + previous.duration) > gap { groups.append([chunk]) }
            else { groups[groups.count - 1].append(chunk) }
        }

        // Term frequencies per conversation, then document frequency across conversations.
        let termCounts: [[String: Int]] = groups.map { group in
            var counts: [String: Int] = [:]
            for chunk in group {
                for token in TextNormalizer.contentTokens(chunk.transcript ?? "") where isKeywordCandidate(token) {
                    counts[token, default: 0] += 1
                }
            }
            return counts
        }
        var documentFrequency: [String: Int] = [:]
        for counts in termCounts { for term in counts.keys { documentFrequency[term, default: 0] += 1 } }
        func weight(_ term: String, _ counts: [String: Int]) -> Double {
            Double(counts[term] ?? 0) * log(1 + Double(groups.count) / Double(documentFrequency[term] ?? 1))
        }

        return groups.enumerated().map { i, group in
            let counts = termCounts[i]
            let keywords = counts.keys.sorted { weight($0, counts) != weight($1, counts) ? weight($0, counts) > weight($1, counts) : $0 < $1 }
                .prefix(3).map { $0.capitalized }

            var best: (score: Double, sentence: String)?
            for chunk in group {
                for sentence in AnswerExtractor.split(chunk.transcript ?? "") {
                    let tokens = TextNormalizer.contentTokens(sentence).filter(isKeywordCandidate)
                    guard tokens.count >= 4 else { continue }
                    // Average weight rather than total, so a long garbled sentence can't win on length.
                    let score = tokens.reduce(0) { $0 + weight($1, counts) } / Double(tokens.count)
                    if best == nil || score > best!.score { best = (score, sentence) }
                }
            }
            let start = group.first!.wallStart
            let end = group.map { $0.wallStart + $0.duration }.max()!
            return Episode(id: i, start: start, end: end, chunks: group, title: "\(daypart(start)) conversation",
                           gist: polish(best?.sentence ?? group[0].transcript ?? ""), keywords: Array(keywords))
        }
    }

    /// Generic words that say little about what a conversation was about.
    private static let genericWords: Set<String> = [
        "before", "after", "send", "book", "booked", "calling", "call", "need", "think", "start", "work", "works",
        "know", "make", "take", "come", "back", "going", "great", "good", "amazing", "perfect", "wonderful",
        "excellent", "lovely", "thanks", "sorry", "please", "tonight", "tomorrow", "morning", "evening",
        "agreed", "mister", "missus", "doctor",
    ]

    private static func isKeywordCandidate(_ token: String) -> Bool {
        token.count >= 4 && Int(token) == nil && !genericWords.contains(token)
    }

    private static func daypart(_ seconds: Double) -> String {
        switch seconds / 3600 {
        case ..<11.5: "Morning"
        case ..<14: "Midday"
        case ..<17.5: "Afternoon"
        default: "Evening"
        }
    }

    private static func polish(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = t.first { t = first.uppercased() + t.dropFirst() }
        if let last = t.last, !".!?".contains(last) { t += "." }
        return t
    }
}
