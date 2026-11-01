import Foundation

/// Turns an answer into text that reads well aloud.
nonisolated enum SpeechText {
    static let limit = 600

    /// Collapses whitespace and line breaks, drops markdown emphasis marks, and keeps whole sentences up to about
    /// `limit` characters. Empty in, empty out.
    static func prepare(_ text: String) -> String {
        var t = text.replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "_", with: " ")
        t = t.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return WatchAnswer.brief(t, limit: limit)
    }
}
