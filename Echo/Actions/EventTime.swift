import Foundation

/// When something was said to happen.
nonisolated struct EventWhen: Equatable, Sendable {
    /// The day, at the clock time said, or at the usual hour for the part of the day ("morning").
    var date: Date
    /// An actual clock time was said ("at 10", "3 pm").
    var hasClock: Bool
    /// How it was said.
    var phrase: String
}

/// Finds a day and a time of day in a sentence, the way the recognizer writes them: "Friday at 10 in the morning", "November 20",
/// "tomorrow first thing", "at three in the afternoon". Relative days ("tomorrow") are counted from `reference`, the moment the
/// sentence was said, not from now, so a promise made last week to do something "tomorrow" is placed correctly.
nonisolated enum EventTime {
    private static let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7, "august": 8,
                                 "september": 9, "october": 10, "november": 11, "december": 12]
    private static let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7]
    private static let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
                                      "ten": 10, "eleven": 11, "twelve": 12]
    private static let ordinalWords: [String: Int] = {
        let names = ["first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth", "eleventh", "twelfth",
                     "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth"]
        var map = Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, $0 + 1) })
        map["twenty first"] = 21; map["twenty second"] = 22; map["twenty third"] = 23; map["twenty fourth"] = 24; map["twenty fifth"] = 25
        map["twenty sixth"] = 26; map["twenty seventh"] = 27; map["twenty eighth"] = 28; map["twenty ninth"] = 29; map["thirtieth"] = 30
        map["thirty first"] = 31
        return map
    }()

    private static func rx(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern, options: .caseInsensitive) }

    private static let monthPattern = months.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let ordinalAlternation = ordinalWords.keys.sorted { $0.count > $1.count }.map { $0.replacingOccurrences(of: " ", with: "[ -]") }.joined(separator: "|")
    private static let monthDay = rx(#"\b(\#(monthPattern))\s+(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\b"#)
    private static let monthOrdinal = rx(#"\b(\#(monthPattern))\s+(?:the\s+)?(\#(ordinalAlternation))\b"#)
    private static let dayOfMonth = rx(#"\b(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+of\s+(\#(monthPattern))\b"#)
    private static let weekday = rx(#"\b(?:(next|this|on)\s+)?(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#)
    private static let relative = rx(#"\bday after tomorrow\b|\btomorrow\b|\btonight\b|\btoday\b|\bthis (?:morning|afternoon|evening)\b|\bthis weekend\b"#)
    private static let partOfDay = rx(#"\bfirst thing\b|\bmorning\b|\bafternoon\b|\bevening\b|\bnight\b|\bnoon\b|\bmidnight\b"#)

    // Clock times. Digits with am/pm; "at 10"; "10 in the morning"; spoken "at three", "ten in the morning"; noon and midnight.
    private static let clockAmPm = rx(#"\b(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\b\.?"#)
    private static let clockAt = rx(#"\bat\s+(\d{1,2})(?::(\d{2}))?\b(?!\s*(?:percent|%|dollars?|people|minutes?|hours?))"#)
    private static let clockInThe = rx(#"\b(\d{1,2})(?::(\d{2}))?\s+in the\s+(morning|afternoon|evening)\b"#)
    private static let clockWordAt = rx(#"\bat\s+(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\s+(o'?clock|thirty|fifteen|forty[- ]five))?\b"#)
    private static let clockWordIn = rx(#"\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\s+(o'?clock|thirty|fifteen|forty[- ]five))?\s+in the\s+(morning|afternoon|evening)\b"#)
    private static let noonMidnight = rx(#"\bnoon\b|\bmidnight\b"#)

    private static func int(_ s: String) -> Int? { Int(s) ?? numberWords[s.lowercased()] }

    private static func substring(_ text: String, _ r: NSRange) -> String { r.location == NSNotFound ? "" : (text as NSString).substring(with: r) }

    /// A clock time, with where in the text it was said. `period` is "morning", "afternoon", "evening", "am" or "pm" when the sentence says so.
    static func clock(in text: String) -> (hour: Int, minute: Int, range: NSRange)? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        func resolve(_ hour: Int, _ minute: Int, period: String?, in range: NSRange) -> (Int, Int, NSRange)? {
            guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
            var h = hour
            switch period?.lowercased() {
            case "a", "am", "morning": if h == 12 { h = 0 }
            case "p", "pm", "afternoon", "evening": if h < 12 { h += 12 }
            default:
                // no period said: small hours are most likely afternoon ("at three"), the 7 to 11 range morning
                if h >= 1 && h <= 6 { h += 12 }
            }
            return (h, minute, range)
        }
        if let m = clockAmPm.firstMatch(in: text, range: full), let h = Int(substring(text, m.range(at: 1))) {
            return resolve(h, Int(substring(text, m.range(at: 2))) ?? 0, period: substring(text, m.range(at: 3)), in: m.range)
        }
        if let m = clockInThe.firstMatch(in: text, range: full), let h = Int(substring(text, m.range(at: 1))) {
            return resolve(h, Int(substring(text, m.range(at: 2))) ?? 0, period: substring(text, m.range(at: 3)), in: m.range)
        }
        if let m = clockWordIn.firstMatch(in: text, range: full), let h = numberWords[substring(text, m.range(at: 1)).lowercased()] {
            return resolve(h, minutes(substring(text, m.range(at: 2))), period: substring(text, m.range(at: 3)), in: m.range)
        }
        if let m = clockWordAt.firstMatch(in: text, range: full), let h = numberWords[substring(text, m.range(at: 1)).lowercased()] {
            // "at three in the afternoon" is handled above; here the period, if any, follows a few words later
            return resolve(h, minutes(substring(text, m.range(at: 2))), period: nil, in: m.range)
        }
        if let m = clockAt.firstMatch(in: text, range: full), let h = Int(substring(text, m.range(at: 1))), h <= 12 || h >= 13 && h <= 23 {
            let after = ns.substring(from: m.range.location + m.range.length).lowercased()
            let period = after.hasPrefix(" in the morning") ? "morning" : (after.hasPrefix(" in the afternoon") ? "afternoon" : (after.hasPrefix(" in the evening") ? "evening" : nil))
            return resolve(h, Int(substring(text, m.range(at: 2))) ?? 0, period: period, in: m.range)
        }
        if let m = noonMidnight.firstMatch(in: text, range: full) {
            return substring(text, m.range).lowercased() == "noon" ? (12, 0, m.range) : (0, 0, m.range)
        }
        return nil
    }

    private static func minutes(_ word: String) -> Int {
        switch word.lowercased() {
        case "thirty": 30
        case "fifteen": 15
        case "forty five", "forty-five": 45
        default: 0
        }
    }

    /// The day a sentence is about (at the start of that day), counted from `reference`, and where it said so.
    private static func day(in text: String, reference: Date, calendar: Calendar) -> (date: Date, range: NSRange)? {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let today = calendar.startOfDay(for: reference)
        func plus(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }
        func nextOccurrence(month: Int, day: Int) -> Date? {
            let year = calendar.component(.year, from: today)
            guard let thisYear = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return thisYear >= today ? thisYear : calendar.date(from: DateComponents(year: year + 1, month: month, day: day))
        }
        if let m = monthDay.firstMatch(in: text, range: full), let mo = months[substring(text, m.range(at: 1)).lowercased()], let d = Int(substring(text, m.range(at: 2))), (1...31).contains(d),
           let date = nextOccurrence(month: mo, day: d) { return (date, m.range) }
        if let m = monthOrdinal.firstMatch(in: text, range: full), let mo = months[substring(text, m.range(at: 1)).lowercased()],
           let d = ordinalWords[substring(text, m.range(at: 2)).lowercased().replacingOccurrences(of: "-", with: " ")], let date = nextOccurrence(month: mo, day: d) { return (date, m.range) }
        if let m = dayOfMonth.firstMatch(in: text, range: full), let d = Int(substring(text, m.range(at: 1))), let mo = months[substring(text, m.range(at: 2)).lowercased()],
           let date = nextOccurrence(month: mo, day: d) { return (date, m.range) }
        if let m = relative.firstMatch(in: text, range: full) {
            let word = substring(text, m.range).lowercased()
            switch word {
            case "day after tomorrow": return plus(2).map { ($0, m.range) }
            case "tomorrow": return plus(1).map { ($0, m.range) }
            case "this weekend":
                let weekdayNow = calendar.component(.weekday, from: today)
                return plus(weekdayNow == 1 || weekdayNow == 7 ? 0 : 7 - weekdayNow).map { ($0, m.range) }
            default: return (today, m.range)   // today, tonight, this morning/afternoon/evening
            }
        }
        if let m = weekday.firstMatch(in: text, range: full), let target = weekdays[substring(text, m.range(at: 2)).lowercased()] {
            let qualifier = substring(text, m.range(at: 1)).lowercased()
            let weekdayNow = calendar.component(.weekday, from: today)
            var ahead = (target - weekdayNow + 7) % 7
            if ahead == 0 && qualifier != "this" { ahead = 7 }
            // "next Tuesday", said on a Monday, means the Tuesday of next week rather than tomorrow
            if qualifier == "next" && ahead >= 1 && ahead <= 2 { ahead += 7 }
            return plus(ahead).map { ($0, m.range) }
        }
        return nil
    }

    /// The default hour for a part of the day, when no clock time was said.
    private static func defaultHour(in text: String) -> Int {
        let p = text.lowercased()
        if p.contains("first thing") { return 8 }
        if p.contains("morning") { return 9 }
        if p.contains("afternoon") { return 15 }   // before "noon", which it contains
        if p.contains("noon") { return 12 }
        if p.contains("evening") { return 18 }
        if p.contains("night") { return 20 }
        return 9
    }

    static func find(in text: String, reference: Date, calendar: Calendar = .current) -> EventWhen? {
        let dayHit = day(in: text, reference: reference, calendar: calendar)
        let clockHit = clock(in: text)
        guard dayHit != nil || clockHit != nil else { return nil }
        let base = dayHit?.date ?? calendar.startOfDay(for: reference)
        let hour: Int, minute: Int
        if let c = clockHit { hour = c.hour; minute = c.minute } else { hour = defaultHour(in: text); minute = 0 }
        guard var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) else { return nil }
        // "today", said after the usual nine o'clock, means by the end of the day rather than a time already gone
        if clockHit == nil, base == calendar.startOfDay(for: reference), date <= reference, partOfDay.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) == nil {
            date = max(calendar.date(bySettingHour: 17, minute: 0, second: 0, of: base) ?? date, reference.addingTimeInterval(3600))
        }
        let ns = text as NSString
        var lo = Int.max, hi = 0
        for range in [dayHit?.range, clockHit?.range].compactMap({ $0 }) { lo = min(lo, range.location); hi = max(hi, range.location + range.length) }
        // a part of the day right after the day ("Thursday morning") belongs to the phrase
        if let part = partOfDay.matches(in: text, range: NSRange(location: 0, length: ns.length)).first(where: { $0.range.location >= max(0, lo) && $0.range.location <= hi + 12 }) {
            lo = min(lo, part.range.location); hi = max(hi, part.range.location + part.range.length)
        }
        var phrase = lo < hi ? ns.substring(with: NSRange(location: lo, length: hi - lo)).trimmingCharacters(in: .whitespaces) : ""
        if phrase.lowercased().hasPrefix("on ") { phrase = String(phrase.dropFirst(3)) }
        return EventWhen(date: date, hasClock: clockHit != nil, phrase: phrase)
    }
}
