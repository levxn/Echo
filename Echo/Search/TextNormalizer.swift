import Foundation
import NaturalLanguage

/// Normalizes transcripts and queries identically so they can be matched: ASR writes "10" and "4%" and
/// "Mr.", while people ask about "ten", "four percent" and "Mister".
nonisolated enum TextNormalizer {
    private static let ones: [String: Int] = [
        "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8,
        "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
        "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30,
    ]
    private static let ordinals: [String: Int] = [
        "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
        "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13, "fourteenth": 14,
        "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18, "nineteenth": 19,
        "twentieth": 20, "thirtieth": 30,
    ]
    private static let aliases: [String: String] = [
        "mr": "mister", "dr": "doctor", "mrs": "missus", "ok": "okay",
        // Derivations the porter stemmer won't join ("decide" vs "decision").
        "decision": "decide", "decisions": "decide", "renewal": "renew", "renewing": "renew",
        "arrival": "arrive", "payment": "pay", "payments": "pay", "commitment": "commit", "commitments": "commit",
    ]

    /// Titles identify a person rather than a topic; they get almost no weight when picking an answer sentence.
    static let titles: Set<String> = ["mister", "doctor", "missus"]

    /// Names of people, places and organizations in a raw query ("Brennan", "Priya"), normalized.
    static func nameTokens(in text: String) -> Set<String> {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var out: Set<String> = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            if let tag, [.personalName, .placeName, .organizationName].contains(tag) {
                tokens(String(text[range])).forEach { out.insert($0) }
            }
            return true
        }
        return out
    }

    /// A person's name found in raw text, as written ("Priya"), and whether a title came right before it
    /// ("Dr. Patel": usually someone being talked *about*, not talked *to*).
    struct NameMention: Equatable {
        let name: String
        let titled: Bool
    }

    private static let titleWords: Set<String> = ["mr", "mister", "dr", "doctor", "mrs", "missus", "ms", "miss"]
    private static let notNames: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "january", "february", "march",
        "april", "may", "june", "july", "august", "september", "october", "november", "december", "okay", "yes",
        "thanks", "thank", "hello", "right", "great", "sure", "perfect", "good", "excellent", "wonderful", "lovely",
        "sorry", "also", "the", "and", "but", "now", "that", "this", "what", "where", "when", "who", "why", "how",
    ]
    private static let capitalizedWord = try! NSRegularExpression(pattern: #"\b[A-Z][a-z]{2,}\b"#)

    /// People named in raw text, in order of appearance. Best effort, and honest about it: Apple's tagger on short
    /// ASR fragments misses lone first names ("Priya") and files others under places ("Jordan"), so a capitalized
    /// word in mid-sentence also counts, unless the tagger says it is a place or organization ("Lisbon", "API").
    static func personNames(in text: String) -> [NameMention] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var found: [(range: Range<String.Index>, titled: Bool)] = []
        var blocked: [Range<String.Index>] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            switch tag {
            case .personalName:
                let first = text[range].split(whereSeparator: { !$0.isLetter }).first.map { $0.lowercased() } ?? ""
                found.append((range, titleWords.contains(first) || titleBefore(range, in: text)))
            case .placeName, .organizationName:
                blocked.append(range)
            default: break
            }
            return true
        }
        for match in capitalizedWord.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            let word = text[range].lowercased()
            if notNames.contains(word) || titleWords.contains(word) { continue }
            if blocked.contains(where: { $0.overlaps(range) }) || found.contains(where: { $0.range.overlaps(range) }) { continue }
            // The first word of a sentence is capitalized anyway, so it says nothing.
            let before = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if before.isEmpty || ".?!".contains(before.last!) { continue }
            found.append((range, titleBefore(range, in: text)))
        }
        return found.sorted { $0.range.lowerBound < $1.range.lowerBound }
            .map { NameMention(name: String(text[$0.range]), titled: $0.titled) }
    }

    /// Single capitalized words the tagger files as places ("Lisbon", and wrongly "Jordan").
    static func placeWords(in text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        var out: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let word = String(text[range])
            if tag == .placeName, word.first?.isUppercase == true, word.allSatisfy({ $0.isLetter }) { out.append(word) }
            return true
        }
        return out
    }

    private static func titleBefore(_ range: Range<String.Index>, in text: String) -> Bool {
        let before = text[..<range.lowerBound].trimmingCharacters(in: CharacterSet(charactersIn: " .").union(.whitespacesAndNewlines))
        let word = before.split(whereSeparator: { !$0.isLetter }).last.map { $0.lowercased() } ?? ""
        return titleWords.contains(word)
    }

    static let stopwords: Set<String> = [
        "a", "about", "after", "again", "all", "also", "am", "an", "and", "any", "are", "as", "at", "be", "been",
        "but", "by", "can", "could", "did", "do", "does", "doing", "done", "for", "from", "get", "go", "going",
        "got", "had", "has", "have", "he", "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it",
        "its", "just", "let", "like", "me", "my", "no", "not", "now", "of", "off", "on", "one", "or", "our",
        "out", "she", "should", "so", "some", "tell", "than", "that", "the", "their", "them", "then", "there",
        "these", "they", "this", "to", "too", "up", "us", "was", "we", "were", "what", "when", "where", "which",
        "who", "why", "will", "with", "would", "yes", "you", "your", "say", "said", "says", "people", "today",
        "thing", "things", "yeah", "well", "okay", "oh", "right", "sure", "thanks", "thank",
        "around", "during", "between", "since", "until", "over", "under", "very", "really", "more", "most",
        "much", "many", "other", "such",
    ]

    /// All normalized tokens, in order, stopwords included.
    static func tokens(_ text: String) -> [String] {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "%", with: " percent ")
        s = s.replacingOccurrences(of: "\u{2019}", with: "'")
        s = s.replacingOccurrences(of: "'s ", with: " ").replacingOccurrences(of: "'", with: "")   // Mom's -> mom
        let raw = s.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)

        var out: [String] = []
        var i = 0
        while i < raw.count {
            var t = raw[i]
            // "20th" / "1st" -> "20" / "1"
            if let digits = stripOrdinalSuffix(t) { t = digits }
            if let tens = ones[t], tens >= 20 || t == "twenty" || t == "thirty" {
                // "twenty first", "thirty one" -> 21, 31
                var value = tens
                if i + 1 < raw.count {
                    let next = raw[i + 1]
                    if let o = ones[next], o < 10 { value += o; i += 1 }
                    else if let o = ordinals[next], o < 10 { value += o; i += 1 }
                }
                out.append(String(value))
            } else if let n = ones[t], t != "one" {          // a lone "one" is a pronoun/article, not a number
                out.append(String(n))
            } else if let n = ordinals[t], t != "first" && t != "second" {
                out.append(String(n))
            } else {
                out.append(aliases[t] ?? t)
            }
            i += 1
        }
        return out
    }

    /// Tokens with stopwords removed: what gets indexed and searched.
    static func contentTokens(_ text: String) -> [String] {
        tokens(text).filter { !stopwords.contains($0) && $0.count > 1 || Int($0) != nil }
    }

    /// Dictionary forms of the words in `text` ("coming" -> "come", "plumbers" -> "plumber"), used to match
    /// query terms against words for highlighting and sentence scoring. Ranking itself uses FTS5's porter
    /// tokenizer, so the two stay consistent where it matters.
    static func lemmas(_ text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var out: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            out.append((tag?.rawValue ?? String(text[range])).lowercased())
            return true
        }
        return out
    }

    /// Lemmas of the normalized form of `text` (digits, titles and spoken numbers already unified).
    static func normalizedLemmas(_ text: String) -> Set<String> {
        Set(lemmas(tokens(text).joined(separator: " ")))
    }

    /// Text stored in the FTS index.
    static func normalized(_ text: String) -> String { contentTokens(text).joined(separator: " ") }

    private static func stripOrdinalSuffix(_ token: String) -> String? {
        for suffix in ["st", "nd", "rd", "th"] where token.hasSuffix(suffix) {
            let head = String(token.dropLast(2))
            if !head.isEmpty, head.allSatisfy(\.isNumber) { return head }
        }
        return nil
    }
}
