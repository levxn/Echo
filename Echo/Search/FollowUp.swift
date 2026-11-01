import Foundation

/// Follow-up questions ("Which of those is due first?"). Echo doesn't send earlier answers anywhere: a follow-up just carries
/// the earlier question along, so the search, the router and the request all see what "those" refers to. Whatever is sent is
/// exactly that combined text, and the review sheet and the ledger show it.
nonisolated enum FollowUp {
    /// A follow-up older than this starts a fresh conversation.
    static let memory: TimeInterval = 10 * 60
    /// Longer questions stand on their own.
    static let maxWords = 9

    /// Words that only make sense after an earlier question. (Words like "this" or "first" are left out: they appear in
    /// ordinary standalone questions such as "what did I say this week?")
    private static let pronouns: Set<String> = ["it", "its", "that", "those", "these", "them", "they", "their", "he", "him", "his", "she", "her", "hers"]
    private static let phrases = ["which one", "which of", "the first one", "the second one", "the last one", "the other one", "the same"]
    private static let openers = ["and ", "what about", "how about", "who else", "what else", "tell me more", "more about", "also "]

    /// True for a short question that leans on an earlier one.
    static func isFollowUp(_ question: String) -> Bool {
        let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = q.split { !($0.isLetter || $0 == "'") }.map(String.init)
        guard !words.isEmpty, words.count <= maxWords else { return false }
        if words.first == "why" || openers.contains(where: { q.hasPrefix($0) }) || phrases.contains(where: { q.contains($0) }) { return true }
        return words.contains { pronouns.contains($0) }
    }

    /// The earlier question (at most its last two sentences, so a long chain doesn't grow without end) followed by the new one.
    static func combine(previous: String, question: String) -> String {
        var parts: [String] = []
        var current = ""
        for ch in previous {
            current.append(ch)
            if "?.!".contains(ch) { parts.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { parts.append(rest) }
        return (parts.suffix(2) + [question]).joined(separator: " ")
    }

    /// What the model is told when the question is a follow-up.
    static let note = "\n\nThe question may be a short follow-up: an earlier question comes first, then the follow-up. Answer the follow-up, using the earlier question to understand what it refers to."
}
