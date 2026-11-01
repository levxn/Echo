import Foundation

/// Turns the phrases the commitments extractor finds ("Wednesday noon", "tomorrow morning", "March 5") into a moment
/// to be reminded. Plain rules, no model. A phrase that can't be placed, or whose time has passed, gives nil.
nonisolated enum DueDate {
    private static let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    private static let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
                                 "september": 9, "october": 10, "november": 11, "december": 12]

    /// The hour a part of the day means, or nil when none was said.
    private static func hour(in phrase: String) -> Int? {
        if phrase.contains("first thing") { return 8 }
        if phrase.contains("morning") { return 9 }
        if phrase.contains("afternoon") { return 15 }   // before "noon", which it contains
        if phrase.contains("noon") { return 12 }
        if phrase.contains("evening") { return 18 }
        if phrase.contains("night") { return 20 }
        return nil
    }

    static func resolve(_ phrase: String, now: Date, calendar: Calendar = .current) -> Date? {
        let p = phrase.lowercased().trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return nil }
        let today = calendar.startOfDay(for: now)
        func at(_ day: Date, _ hour: Int) -> Date? { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) }
        func future(_ date: Date?) -> Date? { date.flatMap { $0 > now ? $0 : nil } }

        if p.contains("tonight") { return future(at(today, 20)) }
        if p.contains("tomorrow") {
            return calendar.date(byAdding: .day, value: 1, to: today).flatMap { at($0, hour(in: p) ?? 9) }
        }
        if p.contains("this weekend") {
            let weekday = calendar.component(.weekday, from: today)
            let ahead = weekday == 1 || weekday == 7 ? 0 : 7 - weekday
            return calendar.date(byAdding: .day, value: ahead, to: today).flatMap { future(at($0, 10)) }
        }
        if p.hasPrefix("this "), let h = hour(in: p), weekdays.keys.allSatisfy({ !p.contains($0) }) { return future(at(today, h)) }

        if let target = weekdays.first(where: { p.contains($0.key) })?.value {
            let weekday = calendar.component(.weekday, from: today)
            var ahead = (target - weekday + 7) % 7
            if p.contains("next "), ahead == 0 { ahead = 7 }
            return calendar.date(byAdding: .day, value: ahead, to: today).flatMap { future(at($0, hour(in: p) ?? 9)) }
        }

        let words = p.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if let m = words.firstIndex(where: { months[$0] != nil }), m + 1 < words.count, let day = Int(words[m + 1]), (1...31).contains(day) {
            var parts = DateComponents(year: calendar.component(.year, from: today), month: months[words[m]], day: day, hour: 9)
            if let date = calendar.date(from: parts), date > now { return date }
            parts.year = (parts.year ?? 0) + 1
            return calendar.date(from: parts)
        }
        return nil
    }
}

/// One way to be reminded about a commitment.
struct ReminderOption: Identifiable, Equatable {
    let title: String
    let date: Date
    var id: Date { date }
}

nonisolated enum ReminderOptions {
    /// When the commitment is due (if that can be placed), in an hour, and tomorrow morning. Never in the past, never twice.
    static func options(due: String?, now: Date, calendar: Calendar = .current) -> [ReminderOption] {
        func clock(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
        var out: [ReminderOption] = []
        if let due, let date = DueDate.resolve(due, now: now, calendar: calendar) {
            out.append(ReminderOption(title: "When it's due · \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))", date: date))
        }
        out.append(ReminderOption(title: "In an hour", date: now.addingTimeInterval(3_600)))
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow), !out.contains(where: { $0.date == nine }) {
            out.append(ReminderOption(title: "Tomorrow morning · \(clock(nine))", date: nine))
        }
        return out
    }
}
