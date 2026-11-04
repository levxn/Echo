import Foundation
import Testing
@testable import Echo

struct ActionFormatTests {
    private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private let us = Locale(identifier: "en_US")
    /// Monday 2 November 2026, 10:00.
    private var now: Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))! }

    private func item(due: Date?, clock: Bool, allDay: Bool = false) -> ActionItem {
        var i = ActionItem(id: "c#a0", kind: .calendar, title: "Plumber visit", due: due, quote: "q", chunkID: "c", dayId: "d", wallStart: 0, timeLabel: "09:00")
        i.hasClock = clock; i.allDay = allDay
        return i
    }

    /// The system writes a narrow no-break space before AM/PM; compare with an ordinary one.
    private func when(_ item: ActionItem) -> String? {
        ActionFormat.when(item, now: now, calendar: utc, locale: us)?.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private func at(_ day: Int, _ hour: Int = 0) -> Date { utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }

    @Test func nearDaysAreNamedAndFarDaysAreDated() {
        #expect(when(item(due: at(2, 15), clock: true)) == "Today 3:00 PM")
        #expect(when(item(due: at(3, 9), clock: true)) == "Tomorrow 9:00 AM")
        #expect(when(item(due: at(6, 10), clock: true)) == "Fri 10:00 AM")
        #expect(when(item(due: at(14), clock: false, allDay: true)) == "Sat, Nov 14")
        #expect(when(item(due: at(1, 9), clock: true)) == "Yesterday 9:00 AM")
    }

    @Test func aDayWithoutAClockShowsNoTime() {
        #expect(when(item(due: at(3), clock: false)) == "Tomorrow")
        #expect(when(item(due: nil, clock: false)) == nil)
    }

    @Test func voiceOverReadsTheKindTheTitleAndTheWhen() {
        var i = item(due: nil, clock: false); i.person = "Ravi"
        #expect(ActionFormat.spoken(i, when: "Fri 10:00 AM") == "Calendar event, Plumber visit, Fri 10:00 AM, with Ravi")
        #expect(ActionFormat.spoken(item(due: nil, clock: false), when: nil) == "Calendar event, Plumber visit")
    }
}

@MainActor
struct ActionsMorningTests {
    private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    @Test func theNextEightAmIsTodayOrTomorrow() {
        let early = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 6))!
        let late = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
        #expect(ActionsMorning.fireDate(now: early, calendar: utc) == utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 8)))
        #expect(ActionsMorning.fireDate(now: late, calendar: utc) == utc.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 8)))
    }

    @Test func theNudgeCarriesACountAndNothingElse() {
        #expect(ActionsMorning.body(count: 1) == "1 thing from your days to review.")
        #expect(ActionsMorning.body(count: 7) == "7 things from your days to review.")
    }

    @Test func nothingIsScheduledWhenOffOrWhenThereIsNothingToReview() async {
        final class Fake: NotificationScheduling {
            var added: [(id: String, body: String)] = []
            var removed: [String] = []
            func ensureAuthorized() async -> Bool { true }
            func add(id: String, title: String, body: String, at date: Date) async throws { added.append((id, body)) }
            func remove(ids: [String]) { removed += ids }
        }
        let fake = Fake()
        let r = Reminders(scheduler: fake, defaults: UserDefaults(suiteName: "echo-morn-\(UUID().uuidString)")!, now: { Date() })
        await r.setMorningActions(enabled: false, count: 5)
        await r.setMorningActions(enabled: true, count: 0)
        #expect(fake.added.isEmpty && fake.removed.count == 2)
        await r.setMorningActions(enabled: true, count: 3)
        #expect(fake.added.map(\.body) == ["3 things from your days to review."] && fake.added[0].id == ActionsMorning.notificationID)
    }
}
