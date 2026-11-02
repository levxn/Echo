import Foundation

/// "Hey Echo": a spoken command. The microphone is never listened to separately for it: the phone hears the same snippets it
/// always does, and when one opens with the wake phrase, the rest is a question, answered on the watch and kept out of memory.
nonisolated enum WakeWord {
    /// "hey echo", with the ways the recognizer tends to write it, at the start of a snippet (after at most "so" or "okay").
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*(?:(?:so|well|um|uh|okay|ok)[,\s]+)?(?:hey|hay|hi|okay|ok)[,\s]+(?:echo|eco|ecko|ekko|echoes)\b[\s,.:;!?\-]*(.*)$"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators])

    /// What follows "Hey Echo" (empty if nothing yet), or nil when the snippet isn't a wake command.
    static func question(in transcript: String) -> String? {
        let range = NSRange(transcript.startIndex..., in: transcript)
        guard let m = pattern.firstMatch(in: transcript, range: range), let r = Range(m.range(at: 1), in: transcript) else { return nil }
        return String(transcript[r]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Decides what a heard snippet is: ordinary conversation, a command, or the question that follows a bare "Hey Echo".
nonisolated struct WakeWordGate: Equatable {
    /// How long a bare "Hey Echo" waits for its question in the next snippet.
    static let patience: TimeInterval = 20

    enum Outcome: Equatable {
        case conversation
        /// A command with its question. Not kept.
        case question(String)
        /// Just "Hey Echo": not kept, and the next snippet is the question.
        case listening
    }

    private(set) var listeningUntil: Date?

    mutating func decide(transcript: String?, now: Date = Date()) -> Outcome {
        let text = (transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .conversation }
        if let rest = WakeWord.question(in: text) {
            if rest.isEmpty { listeningUntil = now.addingTimeInterval(Self.patience); return .listening }
            listeningUntil = nil
            return .question(rest)
        }
        if let until = listeningUntil {
            listeningUntil = nil
            if until > now { return .question(text) }
        }
        return .conversation
    }
}
