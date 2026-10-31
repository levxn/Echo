import Foundation

/// People's names swapped for placeholders (`[PERSON_1]`) before text leaves the phone, and swapped back in the
/// answer that comes home. The mapping exists only in memory on this phone for the one request.
///
/// Best effort, not anonymization: it relies on Apple's on-device name tagger plus a capitalization rule, so a
/// name the tagger misses is sent as it was said, and the UI says so.
nonisolated struct Masking: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let original: String
        let token: String
    }

    var entries: [Entry] = []
    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    private static let boundary = #"(?<![\p{L}\p{N}_])"#
    private static let boundaryEnd = #"(?![\p{L}\p{N}_])"#

    /// Replaces each name as a whole word, any case, longest first. A possessive keeps its 's ("[PERSON_1]'s").
    func mask(_ text: String) -> String {
        var out = text
        for entry in entries.sorted(by: { $0.original.count > $1.original.count }) {
            guard let regex = try? NSRegularExpression(pattern: Self.boundary + NSRegularExpression.escapedPattern(for: entry.original) + Self.boundaryEnd,
                                                       options: .caseInsensitive) else { continue }
            out = regex.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out),
                                                 withTemplate: NSRegularExpression.escapedTemplate(for: entry.token))
        }
        return out
    }

    /// `[PERSON_2]` (with any spacing or case inside the brackets) or a bare `PERSON_2` / `person 2`.
    private static let tokenPattern = try! NSRegularExpression(pattern: #"\[\s*PERSON[_ ]?(\d+)\s*\]|\bPERSON[_ ]?(\d+)\b"#, options: .caseInsensitive)

    /// Puts the names back. Tolerates the model changing case or dropping the brackets; a number this request
    /// never used is left as written.
    func restore(_ text: String) -> String {
        guard !entries.isEmpty else { return text }
        var out = text
        for match in Self.tokenPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let group = match.range(at: 1).location != NSNotFound ? 1 : 2
            guard let whole = Range(match.range, in: out), let digits = Range(match.range(at: group), in: out),
                  let n = Int(out[digits]), let entry = entries.first(where: { $0.token == "[PERSON_\(n)]" }) else { continue }
            out.replaceSubrange(whole, with: entry.original)
        }
        return out
    }
}

nonisolated enum Pseudonymizer {
    /// The tagger files some first names under "place" ("Jordan"). A capitalized word it calls a place but that
    /// turns up in this many separate moments is being used to address someone, so it is masked as a person.
    static let addressedThreshold = 3

    /// `texts` is what will be sent; `corpus` is the whole day, used only to tell a name that is used to address
    /// someone (it keeps coming up) from a place that is mentioned once.
    static func build(question: String, texts: [String], corpus: [String]? = nil) -> Masking {
        var order: [String] = []                 // first-seen spelling, in order of appearance
        var seen: Set<String> = []
        func add(_ word: String) {
            guard seen.insert(word.lowercased()).inserted else { return }
            order.append(word)
        }
        let titles: Set<String> = ["mr", "mister", "dr", "doctor", "mrs", "missus", "ms", "miss"]
        var placeCounts: [String: Int] = [:]
        var placeSpelling: [String: String] = [:]
        var placeFirstSeen: [String] = []

        let sent = [question] + texts
        for text in sent {
            for mention in TextNormalizer.personNames(in: text) {
                for word in mention.name.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }) {
                    let w = String(word)
                    if w.count > 1, !titles.contains(w.lowercased().trimmingCharacters(in: .punctuationCharacters)) { add(w) }
                }
            }
            for place in TextNormalizer.placeWords(in: text) where placeSpelling[place.lowercased()] == nil {
                placeSpelling[place.lowercased()] = place
                placeFirstSeen.append(place.lowercased())
            }
        }
        for text in corpus ?? texts {
            for place in Set(TextNormalizer.placeWords(in: text).map { $0.lowercased() }) { placeCounts[place, default: 0] += 1 }
        }
        // Only words that are actually in the request, and only if they recur across the day.
        for key in placeFirstSeen where (placeCounts[key] ?? 0) >= addressedThreshold { add(placeSpelling[key] ?? key) }

        return Masking(entries: order.enumerated().map { Masking.Entry(original: $1, token: "[PERSON_\($0 + 1)]") })
    }
}

extension TierTwoPlan {
    /// Names replaced before sending, for the ledger and the disclosure.
    var maskedCount: Int { masking.count }
}
