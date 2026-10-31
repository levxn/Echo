import NaturalLanguage
import SwiftUI

/// Marks the words in a transcript that matched the question, matching on lemmas so "coming" lights up
/// "come" and "Mr." lights up "mister".
enum Highlighter {
    static func attributed(_ text: String, terms: [String], highlight: Color, base: Color) -> AttributedString {
        var out = AttributedString(text)
        out.foregroundColor = base
        let targets = Set(terms).union(terms.flatMap { TextNormalizer.lemmas($0) })
        guard !targets.isEmpty else { return out }

        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let word = String(text[range]).lowercased()
            let candidates = [word, tag?.rawValue.lowercased() ?? word] + TextNormalizer.tokens(word)
            if candidates.contains(where: targets.contains),
               let lower = AttributedString.Index(range.lowerBound, within: out),
               let upper = AttributedString.Index(range.upperBound, within: out) {
                out[lower..<upper].foregroundColor = highlight
                out[lower..<upper].font = .body.weight(.semibold)
            }
            return true
        }
        return out
    }
}
