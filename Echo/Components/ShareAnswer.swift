import SwiftUI

/// Plain text for the system share sheet. Nothing is shared unless the person taps Share, and it is not logged: it goes
/// where they send it, not to Muse.
nonisolated enum ShareText {
    static let footer = "Shared from Echo"

    /// One cited item as a line: "Send the spec (to Ravi, Wednesday noon) at 09:05".
    static func item(title: String, detail: String, when: String, time: String) -> String {
        var line = "• " + title
        let extra = [detail, when].filter { !$0.isEmpty }
        if !extra.isEmpty { line += " (" + extra.joined(separator: ", ") + ")" }
        if !time.isEmpty { line += " at " + time }
        return line
    }

    /// A question, its answer and the lines under it.
    static func answer(question: String, answer: String, lines: [String] = []) -> String {
        var parts = ["Q: " + question, "A: " + answer]
        if !lines.isEmpty { parts.append(lines.joined(separator: "\n")) }
        parts.append(footer)
        return parts.joined(separator: "\n\n")
    }

    /// The day's summary, its action items and the people in it.
    static func digest(summary: String, actions: [(what: String, toWhom: String, due: String, time: String)], people: [String]) -> String {
        var parts = ["My day, summarized by Muse", summary]
        if !actions.isEmpty {
            let lines = actions.map { item(title: $0.what, detail: $0.toWhom, when: $0.due, time: $0.time) }
            parts.append("Action items\n" + lines.joined(separator: "\n"))
        }
        if !people.isEmpty { parts.append("People: " + people.joined(separator: ", ")) }
        parts.append(footer)
        return parts.joined(separator: "\n\n")
    }
}

/// "Share" under an answer, next to "Read aloud".
struct ShareAnswerButton: View {
    let text: String

    var body: some View {
        ShareLink(item: text) {
            Label("Share", systemImage: "square.and.arrow.up")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.teal)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(EchoPressStyle())
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel("Share this answer")
    }
}

/// The two things to do with an answer you are looking at: hear it, or send it on.
struct AnswerActions: View {
    let speak: String
    let share: String
    var id = "answer"

    var body: some View {
        FlowLayout {
            ReadAloudButton(text: speak, id: id)
            ShareAnswerButton(text: share)
        }
    }
}
