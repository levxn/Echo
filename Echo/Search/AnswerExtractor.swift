import Foundation
import NaturalLanguage

struct Answer {
    /// The sentence (plus a short follow-on) that best answers the question.
    let headline: String
    let headlineChunk: ChunkRecord
    let sources: [Hit]
    /// Normalized terms to highlight in the headline and sources.
    let highlightTerms: [String]
}

/// Extractive answers: no model, just the best sentence from the best-matching moments.
enum AnswerExtractor {
    static func extract(from outcome: RetrievalOutcome, sourceCount: Int = 3) -> Answer? {
        let sources = Array(outcome.hits.prefix(sourceCount))
        guard let top = sources.first else { return nil }
        let termLemmas = outcome.knownTerms.map { ($0, Set(TextNormalizer.lemmas($0))) }

        var best: (score: Double, sentences: [String], index: Int, chunk: ChunkRecord)?
        for (rank, hit) in sources.enumerated() {
            let sentences = split(hit.chunk.transcript ?? "")
            for (i, sentence) in sentences.enumerated() {
                let lemmas = TextNormalizer.normalizedLemmas(sentence)
                let matched = termLemmas.filter { !$0.1.isDisjoint(with: lemmas) }.map(\.0)
                let score = matched.reduce(0) { $0 + (outcome.headlineWeights[$1] ?? 1) } - 0.01 * Double(rank)
                if best == nil || score > best!.score { best = (score, sentences, i, hit.chunk) }
            }
        }
        guard let best else { return nil }
        var headline = best.sentences[best.index]
        // Keep a short follow-on sentence ("...about your lease. It ends on December 31.").
        if best.index + 1 < best.sentences.count, best.sentences[best.index + 1].split(separator: " ").count <= 12 {
            headline += " " + best.sentences[best.index + 1]
        }
        return Answer(headline: polish(headline), headlineChunk: best.chunk.id.isEmpty ? top.chunk : best.chunk,
                      sources: sources, highlightTerms: outcome.knownTerms)
    }

    static func split(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var out: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let s = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !s.isEmpty { out.append(s) }
            return true
        }
        return out.isEmpty ? [text] : out
    }

    private static func polish(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = t.first { t = first.uppercased() + t.dropFirst() }
        if let last = t.last, !".!?".contains(last) { t += "." }
        return t
    }
}
