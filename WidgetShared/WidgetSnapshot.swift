import Foundation

/// What the widgets, the watch complication and the Live Activity show: a few promises and two counts, written by the app into the
/// App Group the extensions can read. It holds the sentences the person said and nothing else (no names of files, places or voices).
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Item: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var text: String
        /// "by Friday", as said; nil when no time was mentioned.
        var due: String?
        /// When the reminder will go off, if the person set one.
        var remindAt: Date?
    }

    var updated: Date
    var openCount: Int
    var items: [Item]
    var listening: Bool
    var momentsToday: Int

    static let groupID = "group.levtech.Echo"
    static let storageKey = "echo.widgetSnapshot"
    static let empty = WidgetSnapshot(updated: .distantPast, openCount: 0, items: [], listening: false, momentsToday: 0)
    /// Shown in the widget gallery and while the first real snapshot is on its way.
    static let sample = WidgetSnapshot(updated: Date(), openCount: 2, items: [
        Item(id: "a", text: "Send Ravi the API specification", due: "by Wednesday noon", remindAt: nil),
        Item(id: "b", text: "Call the plumber", due: "tomorrow morning", remindAt: nil)], listening: true, momentsToday: 14)

    static func defaults() -> UserDefaults { UserDefaults(suiteName: groupID) ?? .standard }

    static func load(from defaults: UserDefaults = WidgetSnapshot.defaults()) -> WidgetSnapshot {
        defaults.data(forKey: storageKey).flatMap(decode) ?? .empty
    }

    func save(to defaults: UserDefaults = WidgetSnapshot.defaults()) {
        defaults.set(encoded, forKey: Self.storageKey)
    }

    var encoded: Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WidgetSnapshot? { try? JSONDecoder().decode(WidgetSnapshot.self, from: data) }

    /// One line for a small space: "2 promises open" / "Nothing open".
    var summary: String {
        switch openCount {
        case 0: "Nothing open"
        case 1: "1 promise open"
        default: "\(openCount) promises open"
        }
    }
}

#if canImport(ActivityKit) && os(iOS)
import ActivityKit

/// The Live Activity for a promise that is coming due: the sentence and a countdown to its reminder.
nonisolated struct PromiseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var text: String
        var due: Date
    }
    var title: String
}
#endif
