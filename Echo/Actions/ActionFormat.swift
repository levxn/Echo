import Foundation

/// How an action's time is written on a card and in an editor. Pure, so it can be tested.
nonisolated enum ActionFormat {
    /// "Mon 15:00", "Sat 14 Nov" (all day or no clock), "Today 09:00", "Tomorrow".
    static func when(_ item: ActionItem, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String? {
        guard let due = item.due else { return nil }
        let showClock = item.hasClock && !item.allDay
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        let clock = due.formatted(style)
        switch days {
        case 0: return showClock ? "Today \(clock)" : "Today"
        case 1: return showClock ? "Tomorrow \(clock)" : "Tomorrow"
        case -1: return showClock ? "Yesterday \(clock)" : "Yesterday"
        default:
            var day = Date.FormatStyle(locale: locale, calendar: calendar)
            day.timeZone = calendar.timeZone
            let label = abs(days) < 7 ? due.formatted(day.weekday(.abbreviated)) : due.formatted(day.weekday(.abbreviated).day().month(.abbreviated))
            return showClock ? "\(label) \(clock)" : label
        }
    }

    /// What VoiceOver reads for a card: "Calendar event, Plumber visit, Friday 10:00, from the plumber chat".
    static func spoken(_ item: ActionItem, when: String?) -> String {
        [item.kind.label, item.title, when, item.person.map { "with \($0)" }].compactMap { $0 }.joined(separator: ", ")
    }
}
