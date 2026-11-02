import Foundation

/// A span of the day (seconds since midnight) a query is anchored to, e.g. "around 3pm" or "in the evening".
nonisolated struct TimeWindow: Equatable, Sendable {
    let start: Double
    let end: Double
    let label: String

    func overlaps(start s: Double, duration d: Double) -> Bool { s < end && s + d > start }

    /// 1 at the window's center, falling to 0 at its edges.
    func closeness(of s: Double) -> Double {
        let center = (start + end) / 2, half = max(1, (end - start) / 2)
        return max(0, 1 - abs(s - center) / half)
    }
}

nonisolated struct ParsedQuery: Sendable {
    let raw: String
    /// Normalized content words with any time phrase removed.
    let contentTokens: [String]
    let timeWindow: TimeWindow?
    /// The days the question is about, when it names them ("yesterday", "last week").
    var dayScope: DayScope? = nil
}

/// Splits a question into content words and an optional time anchor. Time anchors only *boost* results;
/// they never filter, because a wrong guess about "afternoon" shouldn't hide the right answer.
nonisolated enum QueryParser {
    private static let clock = try! NSRegularExpression(pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)(?![a-z])"#)

    private static let periods: [(word: String, from: Double, to: Double, label: String)] = [
        ("noon", 11.5, 12.5, "around noon"), ("midday", 11.5, 12.5, "around midday"),
        ("lunchtime", 11.5, 14, "lunchtime"), ("lunch", 11.5, 14, "lunchtime"),
        ("breakfast", 6, 10, "breakfast time"), ("morning", 5, 12, "the morning"),
        ("afternoon", 12, 17, "the afternoon"), ("dinnertime", 17.5, 21, "dinnertime"),
        ("dinner", 17.5, 21, "dinnertime"), ("evening", 17, 22, "the evening"), ("tonight", 18, 24, "tonight"),
    ]

    static func parse(_ query: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedQuery {
        var text = query.lowercased()
        var window: TimeWindow?
        var scope: DayScope?
        if let found = DayScope.parse(text, now: now, calendar: calendar) {
            scope = found.scope
            text = found.remainder
        }

        let ns = text as NSString
        if let m = clock.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            var hour = Int(ns.substring(with: m.range(at: 1))) ?? 0
            let minute = m.range(at: 2).location != NSNotFound ? Int(ns.substring(with: m.range(at: 2))) ?? 0 : 0
            let pm = ns.substring(with: m.range(at: 3)).hasPrefix("p")
            if hour == 12 { hour = pm ? 12 : 0 } else if pm { hour += 12 }
            let center = Double(hour * 3600 + minute * 60)
            window = TimeWindow(start: center - 2700, end: center + 2700,
                                label: "around \(DemoClock.format(center))")
            text = ns.replacingCharacters(in: m.range, with: " ")
        } else {
            let words = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
            if let p = periods.first(where: { words.contains($0.word) }) {
                window = TimeWindow(start: p.from * 3600, end: p.to * 3600, label: p.label)
                text = text.replacingOccurrences(of: p.word, with: " ")
            }
        }
        return ParsedQuery(raw: query, contentTokens: TextNormalizer.contentTokens(text), timeWindow: window, dayScope: scope)
    }
}
