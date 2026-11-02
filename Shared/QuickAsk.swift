import Foundation

extension Wire {
    static let demoStart = "demo.start"      // phone -> watch: start the replay (demo driver)
    static let demoQuickAsk = "demo.quickask" // phone -> watch: run preset N (demo driver)
    static let presetKey = "i"
    static let countKey = "count"            // watch -> phone, with "finished": how many snippets it sent in all
    static let ask = "ask"                   // watch -> phone: answer this question
    static let questionKey = "q"
    static let answerKey = "a"
    static let tierKey = "tier"
    static let millisecondsKey = "ms"

    // Voice questions and history.
    static let transcribe = "ask.transcribe" // watch -> phone: a recorded question; the reply carries what was heard
    static let history = "history"           // watch -> phone: send me the recent questions and answers
    static let demoVoiceAsk = "demo.voiceask" // phone -> watch: run recorded question N, as if spoken (demo driver)
    static let audioKey = "audio"
    static let heardKey = "heard"
    static let reasonKey = "reason"
    static let viaKey = "via"
    static let itemsKey = "items"
    static let speakKey = "speak"
    static let announceKey = "announce"      // phone -> watch (application context): buzz every 10 minutes while listening
    static let promiseCaught = "promise.caught" // phone -> watch: a promise was just heard
    static let keepPromise = "promise.keep"     // watch -> phone: remind me about it
    static let idKey = "id"
    static let textKey = "text"
    static let dueKey = "due"
    static let forget = "forget"             // watch -> phone: forget the last N minutes
    static let minutesKey = "minutes"
}

/// A question the watch can ask without a keyboard.
nonisolated struct QuickAsk: Identifiable, Equatable, Sendable {
    let label: String
    let symbol: String
    let question: String
    /// Needs synthesis, so the phone will route it to Muse (the router decides; a test keeps this honest).
    let usesCloud: Bool
    var id: String { question }

    static let presets: [QuickAsk] = [
        QuickAsk(label: "Plumber", symbol: "wrench.and.screwdriver", question: "When is the plumber coming?", usesCloud: false),
        QuickAsk(label: "Priya's trip", symbol: "airplane", question: "Where is Priya going in March?", usesCloud: false),
        QuickAsk(label: "My promises", symbol: "checkmark.circle", question: "What did I promise people today?", usesCloud: true),
        QuickAsk(label: "My day", symbol: "sun.horizon", question: "Summarize my day", usesCloud: true),
    ]
}

/// What the phone sends back to the watch: a short answer and where it came from.
nonisolated struct WatchAnswer: Equatable, Sendable {
    enum Source: String, Sendable, Codable {
        case local      // answered on the phone, nothing sent
        case muse       // Muse Spark
        case stub       // the labeled offline stand-in
        case none       // no answer (nothing matched, cloud off, declined, or busy)
    }

    var text: String
    var source: Source
    var milliseconds: Int
    /// What the phone understood from a spoken question, when there was one.
    var heard: String?
    /// The phone's advice for a spoken question: read this answer aloud (the person's setting says so).
    var speak = false

    var dictionary: [String: Any] {
        var d: [String: Any] = [Wire.okKey: true, Wire.answerKey: text, Wire.tierKey: source.rawValue, Wire.millisecondsKey: milliseconds]
        if let heard { d[Wire.heardKey] = heard }
        if speak { d[Wire.speakKey] = true }
        return d
    }

    /// Whole sentences up to about `limit` characters (a watch screen is small); one long sentence is cut at a word.
    static func brief(_ text: String, limit: Int = 220) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count > limit else { return t }
        var out = ""
        var sentence = ""
        for ch in t {
            sentence.append(ch)
            if ".!?".contains(ch) {
                if out.count + sentence.count > limit { break }
                out += sentence
                sentence = ""
            }
        }
        if !out.isEmpty { return out.trimmingCharacters(in: .whitespaces) }
        let cut = t.prefix(limit)
        let words = cut.split(separator: " ", omittingEmptySubsequences: true).dropLast()
        return words.joined(separator: " ") + "…"
    }

    init(text: String, source: Source, milliseconds: Int = 0, heard: String? = nil, speak: Bool = false) {
        self.text = text; self.source = source; self.milliseconds = milliseconds; self.heard = heard; self.speak = speak
    }

    init?(dictionary: [String: Any]) {
        guard dictionary[Wire.okKey] as? Bool == true, let text = dictionary[Wire.answerKey] as? String else { return nil }
        self.init(text: text, source: (dictionary[Wire.tierKey] as? String).flatMap(Source.init) ?? .none,
                  milliseconds: dictionary[Wire.millisecondsKey] as? Int ?? 0, heard: dictionary[Wire.heardKey] as? String,
                  speak: dictionary[Wire.speakKey] as? Bool ?? false)
    }
}
