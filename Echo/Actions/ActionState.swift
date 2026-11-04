import Foundation

nonisolated enum ActionStatus: String, Codable, Sendable { case new, done, dismissed, snoozed }

/// How the person wants to send a message action.
nonisolated enum MessageChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case email, whatsapp, messages
    var id: String { rawValue }
    var title: String { self == .email ? "Email" : (self == .whatsapp ? "WhatsApp" : "Messages") }
    /// The app it opens in.
    var appName: String { title == "Email" ? "Mail" : title }
    var symbol: String { self == .email ? "envelope.fill" : (self == .whatsapp ? "paperplane.fill" : "message.fill") }
}

/// What the person changed about an action before acting on it. Kept, so a half-edited draft is still there when they come back.
nonisolated struct ActionEdits: Codable, Equatable, Sendable {
    var title: String?
    var due: Date?
    /// The person cleared the time.
    var noDate = false
    var durationMinutes: Int?
    var allDay: Bool?
    var items: [String]?
    var notes: String?
    // a message
    var channel: MessageChannel?
    var to: String?
    var subject: String?
    var body: String?
    /// The body is the person's own words (so a newer draft from Muse is offered, not forced on them).
    var bodyEditedByPerson = false
    /// Muse has been asked (or declined) to write this draft, so opening it again doesn't ask again.
    var museAsked: Bool?

    var isEmpty: Bool { self == ActionEdits() }
}

/// What has been done with one action.
nonisolated struct ActionState: Equatable, Sendable {
    var id: String
    var chunkID: String
    var status: ActionStatus
    var changed: Date
    var snoozedUntil: Date?
    /// Where it went: "Calendar", "Mail", "WhatsApp", "Messages", "Reminders", "Phone".
    var handedOffVia: String?
    var edits = ActionEdits()
}

/// The optional 8 am nudge to look at the Actions page. It says how many, and nothing about what.
nonisolated enum ActionsMorning {
    static let key = "echo.actionsMorning"
    static let notificationID = "echo.actions.morning"
    static let hour = 8

    /// The next 8 am.
    static func fireDate(now: Date, calendar: Calendar = .current) -> Date? {
        guard let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { return nil }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }

    static func body(count: Int) -> String { "\(count) thing\(count == 1 ? "" : "s") from your days to review." }
}
