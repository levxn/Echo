import Foundation

/// What an action asks of the person.
nonisolated enum ActionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case calendar, email, message, call, todo, shopping, waiting
    var id: String { rawValue }

    var label: String {
        switch self {
        case .calendar: "Calendar event"
        case .email: "Email"
        case .message: "Message"
        case .call: "Call"
        case .todo: "To-do"
        case .shopping: "Shopping list"
        case .waiting: "Waiting on"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: "calendar"
        case .email: "envelope.fill"
        case .message: "message.fill"
        case .call: "phone.fill"
        case .todo: "checkmark.circle"
        case .shopping: "cart.fill"
        case .waiting: "hourglass"
        }
    }

    /// The button on the card: what happens when it is opened.
    var primaryTitle: String {
        switch self {
        case .calendar: "Review event"
        case .email: "Review email"
        case .message: "Review message"
        case .call: "Review call"
        case .todo: "Review to-do"
        case .shopping: "Review list"
        case .waiting: "Review follow-up"
        }
    }
}

nonisolated enum ActionOrigin: String, Codable, Sendable { case rules, muse }

/// Something that was said that the person may want to act on, with where it came from.
nonisolated struct ActionItem: Identifiable, Equatable, Codable, Sendable {
    var id: String
    var kind: ActionKind
    var title: String
    /// One line of context: "To Ravi", "Asked by Mom", "Voice 3 said they would".
    var detail: String = ""
    /// Who it concerns, when a name is known.
    var person: String?
    /// The voice of the person it is for or from, when the phone could tell (so a name given to that voice later shows up).
    var personVoiceId: String = ""
    var due: Date?
    /// How the time was said ("Friday at 10 in the morning").
    var dueText: String?
    var hasClock = false
    var allDay = false
    var repeatsYearly = false
    var durationMinutes = 30
    /// The things on a shopping list.
    var items: [String] = []
    /// What was said, as the phone heard it.
    var quote: String
    var chunkID: String
    var dayId: String
    var wallStart: Double
    var timeLabel: String
    var speakerId: String = ""
    var origin: ActionOrigin = .rules

    /// A calendar event whose time has passed is no longer something to act on; a to-do that is overdue still is.
    func isStale(now: Date) -> Bool {
        guard kind == .calendar, let due else { return false }
        return due.addingTimeInterval(Double(allDay ? 24 * 3600 : durationMinutes * 60)) < now
    }
}
