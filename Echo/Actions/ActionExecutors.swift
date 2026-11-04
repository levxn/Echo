import EventKit
import Foundation

/// An event to put in the calendar, as the person confirmed it.
nonisolated struct EventRequest: Equatable, Sendable {
    var title: String
    var notes: String
    var start: Date
    var minutes: Int
    var allDay = false
    var repeatsYearly = false
    /// Minutes before the start to alert; nil for no alert.
    var alertMinutes: Int? = 15
}

/// Richer event writing than `CalendarWriting`: all-day and yearly events, an alert, and a look for clashes.
@MainActor
protocol EventWriting: AnyObject {
    func add(_ request: EventRequest) async -> CalendarResult
    /// Titles of events that overlap this time (empty if none, or if the calendar can't be read).
    func conflicts(start: Date, end: Date) async -> [String]
}

extension SystemCalendar: EventWriting {
    func add(_ request: EventRequest) async -> CalendarResult {
        do { guard try await store.requestFullAccessToEvents() else { return .denied } } catch { return .denied }
        guard let calendar = store.defaultCalendarForNewEvents else { return .failed }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = request.title
        event.notes = request.notes
        event.isAllDay = request.allDay
        event.startDate = request.start
        event.endDate = request.allDay ? request.start : request.start.addingTimeInterval(Double(request.minutes) * 60)
        if let alert = request.alertMinutes, !request.allDay { event.addAlarm(EKAlarm(relativeOffset: -Double(alert) * 60)) }
        if request.repeatsYearly { event.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)) }
        do { try store.save(event, span: request.repeatsYearly ? .futureEvents : .thisEvent); return .added } catch { return .failed }
    }

    func conflicts(start: Date, end: Date) async -> [String] {
        // Only reads if access was already given; opening an editor never asks for it.
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        return events.filter { !$0.isAllDay && $0.startDate < end && $0.endDate > start }.compactMap(\.title)
    }
}

/// Reminders (the Reminders app), behind a small interface so tests don't need it.
@MainActor
protocol ReminderWriting: AnyObject {
    /// Adds a to-do. With `listName`, it goes into that list (made if missing); `items` become the list's to-dos.
    func add(title: String, notes: String, due: Date?, hasClock: Bool, listName: String?, items: [String]) async -> CalendarResult
}

final class SystemReminders: ReminderWriting {
    private let store = EKEventStore()

    func add(title: String, notes: String, due: Date?, hasClock: Bool, listName: String?, items: [String]) async -> CalendarResult {
        do { guard try await store.requestFullAccessToReminders() else { return .denied } } catch { return .denied }
        var list = store.defaultCalendarForNewReminders()
        if let listName {
            list = store.calendars(for: .reminder).first { $0.title == listName && $0.allowsContentModifications }
            if list == nil {
                let made = EKCalendar(for: .reminder, eventStore: store)
                made.title = listName
                made.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first { $0.sourceType == .local || $0.sourceType == .calDAV }
                if (try? store.saveCalendar(made, commit: true)) != nil { list = made }
            }
        }
        guard let list else { return .failed }
        func make(_ text: String, withDate: Bool) -> EKReminder {
            let r = EKReminder(eventStore: store)
            r.calendar = list
            r.title = text
            r.notes = notes
            if withDate, let due {
                var parts = Calendar.current.dateComponents([.year, .month, .day], from: due)
                if hasClock { parts.hour = Calendar.current.component(.hour, from: due); parts.minute = Calendar.current.component(.minute, from: due) }
                r.dueDateComponents = parts
                if hasClock { r.addAlarm(EKAlarm(absoluteDate: due)) }
            }
            return r
        }
        do {
            if items.isEmpty { try store.save(make(title, withDate: true), commit: true) } else {
                for item in items { try store.save(make(item, withDate: false), commit: false) }
                try store.commit()
            }
            return .added
        } catch { return .failed }
    }
}

extension ActionItem {
    /// The action as a promise, so the existing reminder (notification) and draft paths can take it.
    var asPromise: Promise {
        Promise(id: id, chunkID: chunkID, kind: .commitment, timeLabel: timeLabel, wallStart: wallStart, sentence: title.isEmpty ? quote : title,
                toWhom: person, due: dueText, context: nil, speakerId: speakerId)
    }
}
