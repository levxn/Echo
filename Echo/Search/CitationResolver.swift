import Foundation

/// Maps what Muse cited back to a moment on this phone, so a citation can play its audio.
enum CitationResolver {
    /// "S3" (or "s3", "3") -> 3.
    static func ordinal(of label: String) -> Int? {
        let digits = label.trimmingCharacters(in: .whitespaces).drop { $0 == "S" || $0 == "s" }
        return Int(digits)
    }

    /// First by the snippet label (exact, because labels are numbered within the request), then by the HH:MM time.
    /// Times are rounded to the minute, so when several moments share it, the one whose words best overlap
    /// `detail` wins.
    static func resolve(source: String, sourceTime: String, detail: String,
                        snippets: [Snippet], chunks: [ChunkRecord]) -> ChunkRecord? {
        if let n = ordinal(of: source), snippets.indices.contains(n - 1),
           let chunk = chunks.first(where: { $0.id == snippets[n - 1].chunkID }) {
            return chunk
        }
        let sameMinute = chunks.filter { $0.status == .stored && ($0.wallLabel == sourceTime || $0.stamp() == sourceTime) }
        if sameMinute.count <= 1 { return sameMinute.first }
        let wanted = Set(TextNormalizer.contentTokens(detail))
        return sameMinute.max { overlap($0, wanted) < overlap($1, wanted) }
    }

    private static func overlap(_ chunk: ChunkRecord, _ wanted: Set<String>) -> Int {
        Set(TextNormalizer.contentTokens(chunk.transcript ?? "")).intersection(wanted).count
    }
}

/// Questions worth asking next, offered under an answer.
enum FollowUps {
    static let broad = ["What did I promise people today?", "Summarize my day"]
    static let limit = 3

    /// After a local answer: something about the same person or topic, then the two broad questions.
    static func local(query: String, terms: [String]) -> [String] {
        var out: [String] = []
        if let name = TextNormalizer.personNames(in: query).first?.name {
            out.append("What else did \(name) say?")
        } else if let term = terms.first(where: { $0.count > 3 && !TextNormalizer.titles.contains($0) }) {
            out.append("What else did I hear about \(term)?")
        }
        return clean(out + broad, asked: query)
    }

    /// After a Muse answer: its own suggestions, or the broad questions if it gave none.
    static func cloud(_ answer: CloudAnswer, asked query: String) -> [String] {
        let own = clean(answer.followUps, asked: query)
        return own.isEmpty ? clean(broad, asked: query) : own
    }

    private static func clean(_ questions: [String], asked query: String) -> [String] {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        var seen: Set<String> = [key(query)]
        var out: [String] = []
        for q in questions.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !q.isEmpty && seen.insert(key(q)).inserted {
            out.append(q)
        }
        return Array(out.prefix(limit))
    }
}
