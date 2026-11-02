import Foundation

/// Which days a question is about, when it says ("yesterday", "last week", "a week ago", "3 days ago", "last Monday").
/// Plain rules. A question that says nothing is about every day, with newer memories preferred.
nonisolated struct DayScope: Equatable, Sendable {
    let from: String       // first day, inclusive ("2026-10-26")
    let to: String         // last day, inclusive
    let label: String      // "last week", for the answer to say what it looked at

    func contains(_ dayId: String) -> Bool { dayId.isEmpty || (dayId >= from && dayId <= to) }
    var isSingleDay: Bool { from == to }

    private static let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    private static let numbers = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6]
    private static let pattern = try! NSRegularExpression(
        pattern: #"\b(?:yesterday|today(?:'s)?|this week|last week|this month|last month|a week ago|a month ago|a year ago|(?:this )?past week|last 7 days|my week|the week|(?:\d+|one|two|three|four|five|six) days? ago|last (?:sunday|monday|tuesday|wednesday|thursday|friday|saturday))\b"#,
        options: .caseInsensitive)

    /// The scope a question names, and the question with that phrase taken out (so it isn't searched for as a word).
    static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current) -> (scope: DayScope, remainder: String)? {
        let ns = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let phrase = ns.substring(with: match.range).lowercased()
        guard let scope = resolve(phrase, now: now, calendar: calendar) else { return nil }
        return (scope, ns.replacingCharacters(in: match.range, with: " "))
    }

    private static func resolve(_ phrase: String, now: Date, calendar: Calendar) -> DayScope? {
        let today = calendar.startOfDay(for: now)
        func id(_ date: Date) -> String { DayID.id(for: date, calendar: calendar) }
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today) ?? today }
        func single(_ offset: Int, _ label: String) -> DayScope { DayScope(from: id(day(offset)), to: id(day(offset)), label: label) }

        if phrase.hasPrefix("today") { return DayScope(from: id(today), to: id(today), label: "today") }
        switch phrase {
        case "yesterday": return single(-1, "yesterday")
        case "a week ago": return single(-7, "a week ago")
        case "a month ago": return single(-30, "a month ago")
        case "a year ago": return single(-365, "a year ago")
        case "past week", "this past week", "last 7 days", "my week", "the week":
            return DayScope(from: id(day(-7)), to: id(today), label: "the past week")
        case "this week", "last week":
            guard let week = calendar.dateInterval(of: .weekOfYear, for: today) else { return nil }
            if phrase == "this week" { return DayScope(from: id(week.start), to: id(today), label: "this week") }
            let start = calendar.date(byAdding: .day, value: -7, to: week.start) ?? week.start
            return DayScope(from: id(start), to: id(calendar.date(byAdding: .day, value: -1, to: week.start) ?? week.start), label: "last week")
        case "this month", "last month":
            guard let month = calendar.dateInterval(of: .month, for: today) else { return nil }
            if phrase == "this month" { return DayScope(from: id(month.start), to: id(today), label: "this month") }
            guard let prev = calendar.date(byAdding: .month, value: -1, to: month.start), let span = calendar.dateInterval(of: .month, for: prev) else { return nil }
            return DayScope(from: id(span.start), to: id(calendar.date(byAdding: .day, value: -1, to: span.end) ?? span.end), label: "last month")
        default: break
        }
        if phrase.hasSuffix("ago") {   // "3 days ago", "two days ago"
            let word = phrase.split(separator: " ").first.map(String.init) ?? ""
            guard let n = Int(word) ?? numbers[word], n > 0 else { return nil }
            return single(-n, "\(n) days ago")
        }
        if phrase.hasPrefix("last "), let target = weekdays[String(phrase.dropFirst(5))] {   // the most recent such weekday before today
            let weekday = calendar.component(.weekday, from: today)
            var back = (weekday - target + 7) % 7
            if back == 0 { back = 7 }
            return single(-back, phrase)
        }
        return nil
    }
}
