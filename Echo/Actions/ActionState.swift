import Foundation

nonisolated enum ActionStatus: String, Codable, Sendable { case new, done, dismissed, snoozed }

/// How the person wants to send a message action.
nonisolated enum MessageChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case email, whatsapp, messages
    var id: String { rawValue }
    var title: String { self == .email ? "Email" : (self == .whatsapp ? "WhatsApp" : "Messages") }
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
