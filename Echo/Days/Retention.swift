import Foundation

/// How long Echo keeps memories: 7, 30 or 90 days, or forever. Older days are forgotten automatically.
nonisolated enum Retention {
    static let key = "echo.retentionDays"
    static let defaultDays = 30
    /// `0` means forever.
    static let options: [(days: Int, title: String)] = [(7, "7 days"), (30, "30 days"), (90, "90 days"), (0, "Forever")]

    static func title(days: Int) -> String { options.first { $0.days == days }?.title ?? "\(days) days" }

    /// Days before this one are forgotten. Nil when nothing expires.
    static func cutoff(days: Int, now: Date = Date(), calendar: Calendar = .current) -> String? {
        days > 0 ? DayID.id(offset: -days, from: now, calendar: calendar) : nil
    }
}
