import Foundation

/// What Siri and Shortcuts say back. Pure text from the phone's own memory: nothing here calls a model.
nonisolated enum IntentAnswers {
    /// The promises the person made today, as a sentence Siri can read ("You promised two things: …").
    static func promises(chunks: [ChunkRecord], userName: String, myVoice: String?, done: Set<String> = [], today: String) -> String {
        let todays = chunks.filter { $0.isOn(today) }
        guard !todays.isEmpty else { return "I haven't heard anything today yet." }
        var found = PromiseExtractor.extract(from: todays, userName: userName).filter { $0.kind == .commitment && !done.contains($0.id) }
        if let myVoice { found = found.filter { $0.speakerId.isEmpty || $0.speakerId == myVoice } }
        guard !found.isEmpty else { return "You haven't promised anything today." }
        let lines = found.prefix(4).map { $0.sentence.trimmingCharacters(in: CharacterSet(charactersIn: " .!")) }
        let words = ["one", "two", "three", "four"]
        let count = found.count == 1 ? "one thing" : "\(found.count <= 4 ? words[found.count - 1] : "\(found.count)") things"
        return "You promised \(count): " + lines.joined(separator: ". ") + "."
    }

    /// "Forget the last N minutes" said back.
    static func forgot(count: Int, minutes: Int) -> String {
        count == 0 ? "There was nothing from the last \(minutes) minutes to forget."
                   : "Forgot \(count) \(count == 1 ? "moment" : "moments") from the last \(minutes) minutes."
    }

    /// Siri phrases are free text; keep the minutes sensible.
    static func clampMinutes(_ minutes: Int) -> Int { min(max(minutes, 1), 120) }
}
