import EventKit
import Foundation
import Observation

struct CalendarEvent: Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
}

/// The upcoming part of the person's calendar, behind a small interface so tests don't need it.
protocol CalendarReading: AnyObject {
    /// Events starting between `now` and `now + hours`. Asks permission the first time; empty if it is refused.
    func upcoming(hours: Int, now: Date) async -> [CalendarEvent]
}

final class SystemCalendarReader: CalendarReading {
    private let store = EKEventStore()

    func upcoming(hours: Int, now: Date) async -> [CalendarEvent] {
        guard (try? await store.requestFullAccessToEvents()) == true else { return [] }
        let predicate = store.predicateForEvents(withStart: now, end: now.addingTimeInterval(Double(hours) * 3_600), calendars: nil)
        return store.events(matching: predicate).compactMap { e in
            guard let start = e.startDate, !e.isAllDay else { return nil }
            return CalendarEvent(id: e.eventIdentifier ?? UUID().uuidString, title: e.title ?? "", start: start)
        }
    }
}

extension SystemCalendarReader {
    /// Dev hook: `-seed-calendar` adds an event with someone Echo knows, tomorrow at 13:00, so briefings can be seen working.
    static func seed(title: String, now: Date = Date()) async {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true, let calendar = store.defaultCalendarForNewEvents else { return }
        let cal = Calendar.current
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)), let start = cal.date(bySettingHour: 13, minute: 0, second: 0, of: tomorrow) else { return }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar; event.title = title; event.startDate = start; event.endDate = start.addingTimeInterval(3_600)
        try? store.save(event, span: .thisEvent)
    }
}

/// A briefing to show before one meeting.
struct PlannedBriefing: Equatable {
    let eventID: String
    let person: String
    let title: String
    let fire: Date
    let body: String
}

nonisolated enum BriefingPlanner {
    static let lead: TimeInterval = 15 * 60
    private static let filler: Set<String> = ["with", "and", "the", "for", "meeting", "call", "lunch", "dinner", "coffee", "catch", "chat", "sync", "visit", "about", "from", "your", "our"]

    /// Which of the upcoming events are with someone Echo knows, and when to remind. A briefing goes out 15 minutes before; an
    /// event too close to prepare for, or already begun, gets none. One person per event, the one heard most.
    @MainActor
    static func plan(events: [CalendarEvent], people: [Person], briefing: (Person) -> Briefing, now: Date) -> [PlannedBriefing] {
        var out: [PlannedBriefing] = []
        for event in events.sorted(by: { $0.start < $1.start }) where event.start.addingTimeInterval(-lead) > now {
            let titleWords = Set(event.title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)).subtracting(filler)
            guard let person = people.sorted(by: { $0.count > $1.count }).first(where: { p in p.words.contains { titleWords.contains($0) && $0.count > 2 } }) else { continue }
            let b = briefing(person)
            guard !b.isEmpty else { continue }
            out.append(PlannedBriefing(eventID: event.id, person: person.name, title: "Before you see \(person.name)",
                                       fire: event.start.addingTimeInterval(-lead), body: b.summary))
        }
        return out
    }
}

/// Briefings before meetings: reads the next day of the calendar on this phone, and for each meeting with someone Echo knows,
/// sets a notification 15 minutes ahead. Off until the person turns it on. Nothing here is sent anywhere.
@MainActor
@Observable
final class BriefingCenter {
    static let enabledKey = "echo.briefings"
    static let scheduledKey = "echo.briefingIDs"
    static let idPrefix = "echo.briefing."

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }
    private(set) var planned: [PlannedBriefing] = []
    private let reader: any CalendarReading
    private let scheduler: any NotificationScheduling
    private let defaults: UserDefaults

    init(reader: (any CalendarReading)? = nil, scheduler: any NotificationScheduling, defaults: UserDefaults = .standard) {
        self.reader = reader ?? SystemCalendarReader()
        self.scheduler = scheduler
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
    }

    /// Re-plans the next day's briefings (replacing the ones set before). Safe to call whenever the app opens.
    func refresh(people: [Person], briefing: (Person) -> Briefing, now: Date = Date()) async {
        let previous = defaults.stringArray(forKey: Self.scheduledKey) ?? []
        scheduler.remove(ids: previous)
        defaults.removeObject(forKey: Self.scheduledKey)
        planned = []
        guard enabled, !people.isEmpty else { return }
        guard await scheduler.ensureAuthorized() else { return }
        let events = await reader.upcoming(hours: 24, now: now)
        let plans = BriefingPlanner.plan(events: events, people: people, briefing: briefing, now: now)
        var ids: [String] = []
        for p in plans {
            let id = Self.idPrefix + p.eventID
            if (try? await scheduler.add(id: id, title: p.title, body: p.body, at: p.fire)) != nil { ids.append(id) }
        }
        defaults.set(ids, forKey: Self.scheduledKey)
        planned = plans.filter { ids.contains(Self.idPrefix + $0.eventID) }
    }

    /// Forget my day: the briefings were made from it.
    func clear() {
        scheduler.remove(ids: defaults.stringArray(forKey: Self.scheduledKey) ?? [])
        defaults.removeObject(forKey: Self.scheduledKey)
        planned = []
    }
}
