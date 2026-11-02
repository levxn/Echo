import Foundation

/// How a question was asked.
nonisolated enum AskVia: String, Codable, Sendable, CaseIterable {
    case typed, suggestion, voice, watch, watchVoice, wakeWord

    var isVoice: Bool { self == .voice || self == .watchVoice }

    /// Shown in the history detail.
    var label: String {
        switch self {
        case .typed: "Typed"
        case .suggestion: "A suggestion"
        case .voice: "By voice"
        case .watch: "From the watch"
        case .watchVoice: "From the watch, by voice"
        case .wakeWord: "Said \"Hey Echo\""
        }
    }
}

/// One question and the answer it got, in the short form the history list and the watch use. The phone stores more
/// (the full answer and its citations); this is what crosses to the watch.
nonisolated struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var timestamp: Date
    var question: String
    /// A sentence or two, for list rows.
    var answer: String
    var source: WatchAnswer.Source
    var via: AskVia

    init(id: String = UUID().uuidString, timestamp: Date = Date(), question: String, answer: String,
         source: WatchAnswer.Source, via: AskVia) {
        self.id = id; self.timestamp = timestamp; self.question = question; self.answer = answer
        self.source = source; self.via = via
    }

    /// A plist-friendly form for WatchConnectivity.
    var dictionary: [String: Any] {
        ["id": id, "ts": timestamp.timeIntervalSince1970, "q": question, "a": answer, "src": source.rawValue, "via": via.rawValue]
    }

    init?(dictionary d: [String: Any]) {
        guard let id = d["id"] as? String, let ts = d["ts"] as? Double, let q = d["q"] as? String, !q.isEmpty,
              let a = d["a"] as? String else { return nil }
        self.init(id: id, timestamp: Date(timeIntervalSince1970: ts), question: q, answer: a,
                  source: (d["src"] as? String).flatMap(WatchAnswer.Source.init) ?? .none,
                  via: (d["via"] as? String).flatMap(AskVia.init) ?? .typed)
    }
}

/// "now", "5m", "3h", "2d": how long ago, in the fewest characters (for watch rows).
nonisolated enum AgeLabel {
    static func short(from date: Date, to now: Date = Date()) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return "now" }
        if s < 3_600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3_600)h" }
        return "\(s / 86_400)d"
    }
}
