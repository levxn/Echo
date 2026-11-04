import EventKit
import Foundation
import Observation

enum CalendarResult: Equatable { case added, denied, failed }

/// The calendar, behind a small interface so tests don't need it.
protocol CalendarWriting: AnyObject {
    /// Adds an event, asking permission the first time.
    func addEvent(title: String, notes: String, start: Date, minutes: Int) async -> CalendarResult
}

/// The system calendar (EventKit). Echo only adds events for things you promised.
final class SystemCalendar: CalendarWriting {
    let store = EKEventStore()

    func addEvent(title: String, notes: String, start: Date, minutes: Int) async -> CalendarResult {
        do {
            guard try await store.requestFullAccessToEvents() else { return .denied }
        } catch { return .denied }
        guard let calendar = store.defaultCalendarForNewEvents else { return .failed }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title
        event.notes = notes
        event.startDate = start
        event.endDate = start.addingTimeInterval(Double(minutes) * 60)
        do { try store.save(event, span: .thisEvent); return .added } catch { return .failed }
    }
}

/// A promise's event title: what was promised, without the "I will" and without the due phrase (the event's time says that).
nonisolated enum CalendarTitle {
    static func make(from sentence: String, due: String?) -> String {
        var t = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = t.range(of: #"^(?:i will|i'll|i’ll|i promise to|i am going to|i'm going to|i’m going to|remember to|don't forget to|don’t forget to)\b[\s,.]*"#,
                           options: [.regularExpression, .caseInsensitive]) { t.removeSubrange(r) }
        for tail in [" that's a promise", " that’s a promise", ", I promise", " I promise", " promise"] {
            if let r = t.range(of: tail, options: [.caseInsensitive, .backwards]) { t = String(t[..<r.lowerBound]) }
        }
        if let due, !due.isEmpty, let r = t.range(of: due, options: .caseInsensitive) { t.removeSubrange(r) }
        t = t.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .,;"))
        if t.count > 60, let cut = t.prefix(60).lastIndex(of: " ") { t = String(t[..<cut]) + "…" }
        return t.isEmpty ? "Something you promised" : t.prefix(1).uppercased() + t.dropFirst()
    }
}

/// "Add to Calendar" on a commitment: which have an event, kept on this phone. (The events themselves live in the person's
/// calendar and aren't touched by Forget my day.)
@MainActor
@Observable
final class CalendarLink {
    enum Problem: Equatable {
        case notAllowed, failed
        var message: String {
            switch self {
            case .notAllowed: "Calendar access is off for Echo. Turn it on in Settings to add events."
            case .failed: "Couldn't add that to your calendar. Try again."
            }
        }
    }

    static let key = "echo.calendarAdded"

    private(set) var added: [String: Date] = [:]
    var problem: Problem?
    private let calendar: any CalendarWriting
    private let defaults: UserDefaults

    init(calendar: (any CalendarWriting)? = nil, defaults: UserDefaults = .standard) {
        self.calendar = calendar ?? SystemCalendar()
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode([String: Double].self, from: data) {
            added = stored.mapValues { Date(timeIntervalSince1970: $0) }
        }
    }

    func date(for id: String) -> Date? { added[id] }

    @discardableResult
    func add(_ promise: Promise, at start: Date) async -> Bool {
        problem = nil
        let result = await calendar.addEvent(title: CalendarTitle.make(from: promise.sentence, due: promise.due),
                                             notes: promise.sentence + "\n\nFrom Echo", start: start, minutes: 30)
        switch result {
        case .added:
            added[promise.id] = start
            defaults.set(try? JSONEncoder().encode(added.mapValues(\.timeIntervalSince1970)), forKey: Self.key)
            return true
        case .denied: problem = .notAllowed
        case .failed: problem = .failed
        }
        return false
    }

    /// When the day is forgotten, so is which promises were added (the events stay in the calendar).
    func clear() {
        added = [:]
        problem = nil
        defaults.removeObject(forKey: Self.key)
    }
}

extension ReminderOptions {
    /// When a promise's event could go: at its due time if that can be placed, otherwise tomorrow at nine. Never in the past.
    static func calendarOptions(due: String?, now: Date, calendar: Calendar = .current) -> [ReminderOption] {
        var out: [ReminderOption] = []
        if let due, let date = DueDate.resolve(due, now: now, calendar: calendar) {
            out.append(ReminderOption(title: date.formatted(.dateTime.weekday(.abbreviated).hour().minute()), date: date))
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow), !out.contains(where: { $0.date == nine }) {
            out.append(ReminderOption(title: "Tomorrow \(nine.formatted(.dateTime.hour().minute()))", date: nine))
        }
        return out
    }
}
