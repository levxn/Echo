import Foundation

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
    ]

    static let stopwords: Set<String> = [
        "a", "about", "after", "again", "all", "also", "am", "an", "and", "any", "are", "as", "at", "be", "been",
        "but", "by", "can", "could", "did", "do", "does", "doing", "done", "for", "from", "get", "go", "going",
        "got", "had", "has", "have", "he", "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it",
        "its", "just", "let", "like", "me", "my", "no", "not", "now", "of", "off", "on", "one", "or", "our",
        "out", "she", "should", "so", "some", "tell", "than", "that", "the", "their", "them", "then", "there",
        "these", "they", "this", "to", "too", "up", "us", "was", "we", "were", "what", "when", "where", "which",
        "who", "why", "will", "with", "would", "yes", "you", "your", "say", "said", "says", "people", "today",
        "thing", "things", "yeah", "well", "okay", "oh", "right", "sure", "thanks", "thank",
    ]

    /// All normalized tokens, in order, stopwords included.
    static func tokens(_ text: String) -> [String] {
        var s = text.lowercased()
        s = s.replacingOccurrences(of: "%", with: " percent ")
        s = s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
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
