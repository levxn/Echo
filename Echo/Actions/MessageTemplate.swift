import Foundation

/// The first draft of a message, written on the phone in an instant, so there is something to edit straight away while Muse writes a
/// better one. Anything the draft cannot know is left as a [placeholder] in square brackets.
nonisolated enum MessageTemplate {
    struct Draft: Equatable, Sendable {
        var subject: String
        var body: String
    }

    private static let sendVerbs = try! NSRegularExpression(pattern: #"^(?:send|text|give|share|email|forward|message|tell|bring|show|reply to)\s+"#, options: .caseInsensitive)

    private static let workVerbs = try! NSRegularExpression(pattern: #"^(?:review|finish|finalize|finalise|update|prepare|write|fix|complete|check|approve|sign|ask)\s+"#, options: .caseInsensitive)

    /// "Send the API specification" → "the API specification".
    static func object(of title: String, stripWorkVerb: Bool = false) -> String {
        var t = title.trimmingCharacters(in: .whitespaces)
        if stripWorkVerb { t = workVerbs.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "") }
        t = sendVerbs.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        if let to = t.range(of: #"\s+to\s+[A-Z][\w.’' ]*$"#, options: .regularExpression) { t.removeSubrange(to) }   // "… to Ravi"
        return t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))
    }

    private static func firstName(_ person: String?) -> String? {
        guard let person, !person.isEmpty else { return nil }
        let titles: Set<String> = ["mr", "mr.", "mister", "mrs", "mrs.", "ms", "ms.", "dr", "dr.", "doctor"]
        let words = person.split(separator: " ").map(String.init)
        if words.count >= 2, titles.contains(words[0].lowercased()) { return words.joined(separator: " ") }   // "Mr. Brennan" stays whole
        return words.first
    }

    private static func when(_ item: ActionItem) -> String {
        guard let text = item.dueText, !text.isEmpty else { return "" }
        let lower = text.lowercased()
        let preposition = ["tomorrow", "today", "tonight", "this ", "next "].contains { lower.hasPrefix($0) } ? "" : (lower.hasPrefix("by ") || lower.hasPrefix("before ") ? "" : "for ")
        return " \(preposition)\(text)"
    }

    /// The draft for a message, an email, or a nudge to someone who owes the person something.
    static func draft(for item: ActionItem, channel: MessageChannel, userName: String) -> Draft {
        let name = firstName(item.person)
        let hello = name.map { "Hi \($0)," } ?? "Hi,"
        let me = userName.split(separator: " ").first.map(String.init) ?? userName
        let thing = object(of: item.title, stripWorkVerb: item.kind == .waiting)
        let needsFile = thing.range(of: #"\b(?:specification|spec|document|contract|invoice|report|proposal|slides|deck|presentation|file|files|pdf|attachment|agreement|quote|estimate|budget)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let needsLink = thing.range(of: #"\b(?:link|recipe|photo|photos|picture|pictures|address|location|video|voucher|invite)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        let attach = needsFile ? " [Attach the file]" : (needsLink ? " [Add the link]" : "")

        switch item.kind {
        case .waiting:
            let body = "\(hello)\n\nJust checking in on \(thing.isEmpty ? "this" : thing)\(when(item)). Could you let me know where it stands?"
            return Draft(subject: "Checking in: \(thing.isEmpty ? "our plan" : thing)", body: channel == .email ? body + "\n\nThanks,\n\(me)" : body)
        default:
            let core: String
            if item.title.lowercased().hasPrefix("give a final answer") || item.title.lowercased().contains("answer") || item.title.lowercased().hasPrefix("reply") {
                core = "I wanted to get back to you\(when(item)). [Your answer]"
            } else {
                core = "I'm sending you \(thing.isEmpty ? "what I promised" : thing), as I said I would\(when(item)).\(attach)"
            }
            if channel == .email {
                return Draft(subject: thing.isEmpty ? "What I promised" : thing.prefix(1).uppercased() + thing.dropFirst(), body: "\(hello)\n\n\(core)\n\nBest,\n\(me)")
            }
            return Draft(subject: "", body: "\(hello) \(core)")
        }
    }

    /// Which channel to suggest: documents go by email, everything else is a quick message.
    static func suggestedChannel(for item: ActionItem) -> MessageChannel {
        item.kind == .email ? .email : .whatsapp
    }

    /// Placeholders still waiting to be filled in, so the editor can point at them.
    static func placeholders(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[[^\]\n]{2,40}\]"#) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}
