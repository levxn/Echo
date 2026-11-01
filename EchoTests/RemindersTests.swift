import Foundation
import Testing
@testable import Echo

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

struct DueDateTests {
    /// Sunday 1 November 2026, 5 pm.
    private let sunday = date(2026, 11, 1, 17)

    private func resolve(_ phrase: String, now: Date? = nil) -> Date? { DueDate.resolve(phrase, now: now ?? sunday, calendar: utc) }

    @Test func aDayAndAPartOfTheDayBecomeThatMoment() {
        #expect(resolve("By Wednesday noon") == date(2026, 11, 4, 12))
        #expect(resolve("Friday afternoon") == date(2026, 11, 6, 15))
        #expect(resolve("Wednesday evening") == date(2026, 11, 4, 18))
        #expect(resolve("Tuesday") == date(2026, 11, 3, 9), "no time said means nine in the morning")
        #expect(resolve("On Monday morning") == date(2026, 11, 2, 9))
    }

    @Test func tomorrowTonightAndThisEveningAreRelativeToNow() {
        #expect(resolve("Tomorrow morning") == date(2026, 11, 2, 9))
        #expect(resolve("Tomorrow") == date(2026, 11, 2, 9))
        #expect(resolve("Tomorrow first thing") == date(2026, 11, 2, 8))
        #expect(resolve("Tonight") == date(2026, 11, 1, 20))
        #expect(resolve("This evening") == date(2026, 11, 1, 18))
    }

    @Test func aMomentThatHasAlreadyPassedIsNotOffered() {
        #expect(resolve("Tonight", now: date(2026, 11, 1, 21)) == nil)
        #expect(resolve("This morning") == nil)
        #expect(resolve("Wednesday", now: date(2026, 11, 4, 10)) == nil, "said on Wednesday after nine: today's time has gone")
        #expect(resolve("Wednesday", now: date(2026, 11, 4, 8)) == date(2026, 11, 4, 9))
    }

    @Test func nextMeansAfterTodayAndTheWeekendMeansSaturdayMorning() {
        #expect(resolve("Next Sunday") == date(2026, 11, 8, 9))
        #expect(resolve("This weekend", now: date(2026, 11, 4, 10)) == date(2026, 11, 7, 10))
        #expect(resolve("This weekend", now: date(2026, 11, 7, 8)) == date(2026, 11, 7, 10))
    }

    @Test func aDateUsesThisYearUnlessItHasPassed() {
        #expect(resolve("By November 20") == date(2026, 11, 20, 9))
        #expect(resolve("March 5") == date(2027, 3, 5, 9))
    }

    @Test func thingsItCannotPlaceGiveNothing() {
        for phrase in ["", "soon", "later", "some day", "March", "March 45"] { #expect(resolve(phrase) == nil, "\(phrase)") }
    }

    @Test func optionsOfferTheDueTimeAnHourAndTomorrowMorningWithoutRepeats() {
        let withDue = ReminderOptions.options(due: "Wednesday noon", now: sunday, calendar: utc)
        #expect(withDue.map(\.date) == [date(2026, 11, 4, 12), sunday.addingTimeInterval(3_600), date(2026, 11, 2, 9)])
        #expect(withDue[0].title.hasPrefix("When it's due"))
        let none = ReminderOptions.options(due: nil, now: sunday, calendar: utc)
        #expect(none.count == 2 && none[0].title == "In an hour")
        let same = ReminderOptions.options(due: "Tomorrow morning", now: sunday, calendar: utc)
        #expect(same.map(\.date) == [date(2026, 11, 2, 9), sunday.addingTimeInterval(3_600)], "tomorrow morning is not listed twice")
        #expect(ReminderOptions.options(due: "Tonight", now: date(2026, 11, 1, 21), calendar: utc).allSatisfy { $0.date > date(2026, 11, 1, 21) })
    }
}

@MainActor
private final class FakeNotifications: NotificationScheduling {
    var allowed = true
    var added: [(id: String, title: String, body: String, date: Date)] = []
    var removed: [String] = []
    var failNext = false
    func ensureAuthorized() async -> Bool { allowed }
    func add(id: String, title: String, body: String, at date: Date) async throws {
        if failNext { failNext = false; throw CocoaError(.fileWriteUnknown) }
        added.append((id, title, body, date))
    }
    func remove(ids: [String]) { removed += ids }
}

@MainActor
struct RemindersTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(_ fake: FakeNotifications, defaults: UserDefaults? = nil) -> Reminders {
        Reminders(scheduler: fake, defaults: defaults ?? UserDefaults(suiteName: "echo-rem-\(UUID().uuidString)")!, now: { now })
    }

    private func promise(_ id: String = "c1#0", kind: Promise.Kind = .commitment) -> Promise {
        Promise(id: id, chunkID: "c1", kind: kind, timeLabel: "09:05", wallStart: 0, sentence: "I will send the spec by Wednesday noon.",
                toWhom: "Ravi", due: "By Wednesday noon", context: nil)
    }

    @Test func aReminderIsScheduledWithTheCommitmentAsItsText() async throws {
        let fake = FakeNotifications()
        let r = store(fake)
        let when = now.addingTimeInterval(3_600)
        let ok = await r.schedule(promise(), at: when)
        #expect(ok && r.date(for: "c1#0") == when && r.problem == nil)
        let sent = try #require(fake.added.first)
        #expect(sent.id == "echo.promise.c1#0" && sent.body == "I will send the spec by Wednesday noon." && sent.date == when)
        #expect(sent.title.contains("you said you would"))
    }

    @Test func aHeardReminderSaysSo() async throws {
        let fake = FakeNotifications()
        await store(fake).schedule(promise(kind: .reminder), at: now.addingTimeInterval(60))
        #expect(try #require(fake.added.first).title.contains("a reminder you heard"))
    }

    @Test func movingAReminderReplacesTheOldOne() async {
        let fake = FakeNotifications()
        let r = store(fake)
        await r.schedule(promise(), at: now.addingTimeInterval(3_600))
        await r.schedule(promise(), at: now.addingTimeInterval(7_200))
        #expect(r.date(for: "c1#0") == now.addingTimeInterval(7_200))
        #expect(fake.removed == ["echo.promise.c1#0", "echo.promise.c1#0"], "the earlier one is cleared before each new one")
        #expect(r.scheduled.count == 1)
    }

    @Test func withoutPermissionNothingIsScheduledAndThePersonIsToldWhy() async {
        let fake = FakeNotifications()
        fake.allowed = false
        let r = store(fake)
        let ok = await r.schedule(promise(), at: now.addingTimeInterval(3_600))
        #expect(!ok && fake.added.isEmpty && r.scheduled.isEmpty && r.problem == .notAllowed)
        #expect(Reminders.Problem.notAllowed.message.contains("Settings"))
    }

    @Test func aMomentInThePastAndASystemFailureAreBothRefused() async {
        let fake = FakeNotifications()
        let r = store(fake)
        #expect(await !r.schedule(promise(), at: now.addingTimeInterval(-5)) && r.problem == .failed)
        fake.failNext = true
        #expect(await !r.schedule(promise(), at: now.addingTimeInterval(60)) && r.problem == .failed && r.scheduled.isEmpty)
    }

    @Test func cancellingRemovesItEverywhere() async {
        let fake = FakeNotifications()
        let r = store(fake)
        await r.schedule(promise(), at: now.addingTimeInterval(3_600))
        r.cancel("c1#0")
        #expect(r.date(for: "c1#0") == nil && fake.removed.contains("echo.promise.c1#0"))
    }

    @Test func remindersSurviveARelaunchAndTheOnesThatWentOffAreDropped() async {
        let defaults = UserDefaults(suiteName: "echo-rem-\(UUID().uuidString)")!
        let first = store(FakeNotifications(), defaults: defaults)
        await first.schedule(promise("a#0"), at: now.addingTimeInterval(3_600))
        await first.schedule(promise("b#0"), at: now.addingTimeInterval(100))
        let later = Reminders(scheduler: FakeNotifications(), defaults: defaults, now: { self.now.addingTimeInterval(500) })
        #expect(later.date(for: "a#0") == now.addingTimeInterval(3_600) && later.date(for: "b#0") == nil)
    }

    @Test func forgettingTheDayClearsEveryReminder() async {
        let fake = FakeNotifications()
        let r = store(fake)
        await r.schedule(promise("a#0"), at: now.addingTimeInterval(3_600))
        await r.schedule(promise("b#0"), at: now.addingTimeInterval(7_200))
        fake.removed = []
        r.clearAll()
        #expect(r.scheduled.isEmpty && Set(fake.removed) == ["echo.promise.a#0", "echo.promise.b#0"])
    }
}
