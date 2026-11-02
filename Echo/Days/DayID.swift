import Foundation

/// A day, named by its calendar date ("2026-11-02"), so memories from different days stay apart and sort by time as text.
/// A chunk with no day (the empty string) belongs to whichever day is being asked about: it came from before days existed.
nonisolated enum DayID {
    static func id(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func today(now: Date = Date(), calendar: Calendar = .current) -> String { id(for: now, calendar: calendar) }

    /// The day `offset` days from `now` (-7 is a week ago).
    static func id(offset: Int, from now: Date = Date(), calendar: Calendar = .current) -> String {
        id(for: calendar.date(byAdding: .day, value: offset, to: now) ?? now, calendar: calendar)
    }

    static func date(of id: String, calendar: Calendar = .current) -> Date? {
        let p = id.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// Whole days between `id` and `now` (0 = today, 1 = yesterday). Nil for an empty or malformed id.
    static func daysAgo(_ id: String, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let day = date(of: id, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: day, to: calendar.startOfDay(for: now)).day
    }

    /// "Today", "Yesterday", "Mon" within the last week, otherwise "26 Oct". Empty ids read as today.
    static func shortLabel(_ id: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let ago = daysAgo(id, now: now, calendar: calendar), let day = date(of: id, calendar: calendar) else { return "Today" }
        switch ago {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return day.formatted(.dateTime.weekday(.abbreviated))
        default: return day.formatted(.dateTime.day().month(.abbreviated))
        }
    }

    /// For headings: "Today", "Yesterday", "A week ago", "Mon 26 Oct".
    static func longLabel(_ id: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let ago = daysAgo(id, now: now, calendar: calendar), let day = date(of: id, calendar: calendar) else { return "Today" }
        switch ago {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 7: return "A week ago"
        default: return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }
}
