import Foundation
import Testing
@testable import Echo

struct ListeningPlanTests {
    private let utc: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 2) -> Date { utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))! }
    private let nineToSix = ListeningSettings(mode: .hours, startMinute: 9 * 60, endMinute: 18 * 60)
    private let manual = ListeningSettings()

    private func decide(_ s: ListeningSettings, _ now: Date, listening: Bool = false, was: Bool = false, battery: Double? = 0.8, nudged: Bool = false) -> ListeningPlan.Action {
        ListeningPlan.decide(settings: s, now: now, calendar: utc, isListening: listening, wasListening: was, battery: battery, nudgeSent: nudged)
    }

    @Test func hoursContainTheirStartButNotTheirEnd() {
        #expect(nineToSix.contains(minute: 9 * 60) && nineToSix.contains(minute: 17 * 60 + 59))
        #expect(!nineToSix.contains(minute: 8 * 60 + 59) && !nineToSix.contains(minute: 18 * 60))
        #expect(!ListeningSettings(mode: .hours, startMinute: 600, endMinute: 600).contains(minute: 600), "no hours at all")
    }

    @Test func anOvernightSpanWorksAcrossMidnight() {
        let night = ListeningSettings(mode: .hours, startMinute: 22 * 60, endMinute: 6 * 60)
        #expect(night.contains(minute: 23 * 60) && night.contains(minute: 3 * 60) && !night.contains(minute: 12 * 60))
    }

    @Test func tapOnlyNeverStartsOrStopsByItself() {
        #expect(decide(manual, at(10)) == .none)
        #expect(decide(manual, at(3), listening: true) == .none, "listening in manual mode runs until the person stops it")
    }

    @Test func theHoursNudgeOnceAndStopAtTheEnd() {
        #expect(decide(nineToSix, at(9, 5)) == .nudge)
        #expect(decide(nineToSix, at(9, 5), nudged: true) == .none, "one nudge per day, not a stream of them")
        #expect(decide(nineToSix, at(8)) == .none, "before the hours: nothing")
        #expect(decide(nineToSix, at(12), listening: true) == .none)
        #expect(decide(nineToSix, at(18, 1), listening: true) == .stop(.endOfHours))
    }

    @Test func anInterruptedSessionPicksItselfUpAgainInsideTheHours() {
        #expect(decide(nineToSix, at(12), was: true) == .resume)
        #expect(decide(nineToSix, at(19), was: true) == .none, "after the hours it stays off")
        #expect(decide(manual, at(12), was: true) == .resume, "a tap-only session that was cut off also carries on")
    }

    @Test func lowBatteryStopsListeningAndPreventsAStart() {
        #expect(decide(nineToSix, at(12), listening: true, battery: 0.19) == .stop(.lowBattery))
        #expect(decide(nineToSix, at(12), was: true, battery: 0.1) == .none)
        #expect(decide(nineToSix, at(9, 5), battery: 0.1) == .none, "no nudge to start on a nearly flat watch")
        #expect(decide(nineToSix, at(12), listening: true, battery: nil) == .none, "an unknown level doesn't stop anything")
    }

    @Test func theNextStartIsTodayOrTomorrow() {
        #expect(nineToSix.nextStart(after: at(7), calendar: utc) == at(9))
        #expect(nineToSix.nextStart(after: at(10), calendar: utc) == at(9, day: 3))
        #expect(manual.nextStart(after: at(7), calendar: utc) == nil)
    }

    @Test func modesAreNamedPlainly() {
        #expect(manual.title == "Only when I tap")
        #expect(ListeningSettings.allDay().title == "All day" && ListeningSettings.allDay().isAllDay)
        #expect(nineToSix.title == "9 am – 6 pm")
        #expect(ListeningSettings(mode: .hours, startMinute: 8 * 60 + 30, endMinute: 17 * 60 + 15).title == "8:30 am – 5:15 pm")
    }

    @Test func settingsTravelAsADictionaryAndBadOnesAreRefused() {
        let s = ListeningSettings(mode: .hours, startMinute: 540, endMinute: 1080, stamp: 12.5)
        #expect(ListeningSettings(dictionary: s.dictionary) == s)
        #expect(ListeningSettings(dictionary: ["mode": "nonsense", "start": 1, "end": 2]) == nil)
        #expect(ListeningSettings(dictionary: ["mode": "hours", "start": 2000, "end": 5]) == nil)
    }
}

@MainActor
struct ListeningStoreTests {
    private func store(_ defaults: UserDefaults? = nil, now: Double = 1_000) -> ListeningStore {
        ListeningStore(defaults: defaults ?? UserDefaults(suiteName: "echo-listen-\(UUID().uuidString)")!, now: { Date(timeIntervalSince1970: now) })
    }

    @Test func aChangeIsStampedKeptAndAnnounced() {
        let d = UserDefaults(suiteName: "echo-listen-\(UUID().uuidString)")!
        let s = store(d)
        var told: [ListeningSettings] = []
        s.onChange = { told.append($0) }
        s.set(ListeningSettings(mode: .hours, startMinute: 540, endMinute: 1080))
        #expect(s.settings.stamp == 1_000 && told.count == 1)
        #expect(ListeningStore(defaults: d).settings == s.settings, "kept across launches")
        s.set(s.settings)
        #expect(told.count == 1, "setting the same thing again changes nothing")
    }

    @Test func theNewestChangeWinsWhenTheDevicesDisagree() {
        let s = store(now: 2_000)
        s.set(ListeningSettings(mode: .hours, startMinute: 360, endMinute: 1380))
        #expect(!s.merge(ListeningSettings(mode: .manual, stamp: 1_500)), "older: ignored")
        #expect(s.settings.mode == .hours)
        #expect(s.merge(ListeningSettings(mode: .manual, stamp: 2_500)))
        #expect(s.settings.mode == .manual)
    }

    @Test func aMergedChangeIsNotSentBack() {
        let s = store()
        var told = 0
        s.onChange = { _ in told += 1 }
        s.merge(ListeningSettings(mode: .hours, stamp: 5_000))
        #expect(told == 0, "otherwise the two devices would echo the same change forever")
    }

    @Test func theDevHookSetsTheModeAsIfChosen() {
        let d = UserDefaults(suiteName: "echo-listen-\(UUID().uuidString)")!
        #expect(ListeningStore(defaults: d, now: { Date(timeIntervalSince1970: 7) }, arguments: ["-listen-mode", "allday"]).settings == .allDay(stamp: 7))
        #expect(ListeningStore(defaults: d, now: { Date(timeIntervalSince1970: 8) }, arguments: ["-listen-mode", "manual"]).settings == ListeningSettings(stamp: 8))
        #expect(ListeningStore(defaults: d, now: { Date(timeIntervalSince1970: 9) }, arguments: ["-listen-mode", "nonsense"]).settings.stamp == 8, "an unknown value changes nothing")
    }

    @Test func whetherItWasListeningIsRemembered() {
        let d = UserDefaults(suiteName: "echo-listen-\(UUID().uuidString)")!
        let s = store(d)
        #expect(!s.wasListening)
        s.wasListening = true
        #expect(ListeningStore(defaults: d).wasListening)
    }
}

@MainActor
struct PhoneListeningStateTests {
    private func model() async throws -> (PipelineModel, Harness) {
        let h = try await Harness.make()
        let m = PipelineModel(store: h.store, defaults: UserDefaults(suiteName: "echo-listenstate-\(UUID().uuidString)")!)
        return (m, h)
    }

    @Test func theWatchCountsAsListeningWhileItIsNearAndRunning() async throws {
        let (m, h) = try await model(); defer { h.cleanup() }
        #expect(!m.isListening)
        await m.sessionStarted(total: 0, keepExisting: true)
        m.setReachable(true)
        #expect(m.isListening)
        m.sessionFinished(recorded: 1)
        #expect(!m.isListening, "once the watch says it stopped")
    }

    @Test func pausingOnTheWatchTurnsListeningOffOnThePhoneAndResumingTurnsItBackOn() async throws {
        let (m, h) = try await model(); defer { h.cleanup() }
        await m.sessionStarted(total: 0, keepExisting: true)
        m.setReachable(true)
        #expect(m.isListening && !m.isPaused)
        m.setPaused(true)
        #expect(!m.isListening && m.isPaused, "the microphone is off, so the phone must not say listening")
        m.setPaused(false)
        #expect(m.isListening && !m.isPaused)
        m.setPaused(true)
        await m.sessionStarted(total: 0, keepExisting: true)
        #expect(!m.isPaused, "a new session is not paused")
        m.setPaused(true)
        m.sessionFinished(recorded: 1)
        #expect(!m.isPaused && !m.isListening)
    }

    @Test func aSessionLeftOpenDoesNotMakeAnIdleWatchLookLikeItIsListening() async throws {
        let (m, h) = try await model(); defer { h.cleanup() }
        await m.sessionStarted(total: 0, keepExisting: true)   // the watch app was then force-quit: no "finished" ever came
        m.setReachable(false)
        m.setReachable(true)                                    // it is back, near, and idle
        #expect(m.isListening, "until it says otherwise the phone has to assume the session is live")
        m.setWatchListening(false)
        #expect(!m.isListening, "it says its microphone is off, so the phone says so too")
        m.setWatchListening(true)
        #expect(m.isListening)
        m.setReachable(false)
        #expect(m.watchListening == nil, "out of reach, what it said is out of date")
    }

    @Test func aWatchThatWentQuietWithoutSayingSoStopsCountingAfterThreeMinutes() async throws {
        let (m, h) = try await model(); defer { h.cleanup() }
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        m.now = { clock }
        await m.sessionStarted(total: 0, keepExisting: true)
        m.setReachable(false)
        #expect(m.isListening, "just out of reach, a moment ago: still listening")
        clock = clock.addingTimeInterval(179)
        #expect(m.isListening)
        clock = clock.addingTimeInterval(2)
        #expect(!m.isListening, "force-quit or flat battery: the phone doesn't say listening for ever")
        m.updateRecorded(5)
        #expect(m.isListening, "but audio arriving again means it is")
    }
}

@MainActor
struct ListeningNudgeTests {
    private final class Fake: NotificationScheduling {
        var added: [(id: String, body: String, date: Date)] = []
        var removed: [String] = []
        func ensureAuthorized() async -> Bool { true }
        func add(id: String, title: String, body: String, at date: Date) async throws { added.append((id, body, date)) }
        func remove(ids: [String]) { removed += ids }
    }

    @Test func thePhoneNudgesAtTheNextStartAndNeverInTapOnlyMode() async {
        let fake = Fake()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let r = Reminders(scheduler: fake, defaults: UserDefaults(suiteName: "echo-nudge-\(UUID().uuidString)")!, now: { now })
        await r.setListeningNudge(ListeningSettings())
        #expect(fake.added.isEmpty && fake.removed == [ListeningNudge.notificationID], "tap only: any old nudge is removed, none is made")
        await r.setListeningNudge(ListeningSettings(mode: .hours, startMinute: 9 * 60, endMinute: 18 * 60))
        #expect(fake.added.count == 1 && fake.added[0].id == ListeningNudge.notificationID && fake.added[0].body == "Time to start listening?")
        #expect(fake.added[0].date > now)
    }
}
