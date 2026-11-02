import Foundation
import Testing
@testable import Echo

private func heard(_ id: String, _ text: String, day: String, at wall: Double = 100, speaker: String = "") -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: .stored, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day, speakerId: speaker)
}

private func priya(_ ids: [String]) -> Person { Person(name: "Priya", words: ["priya"], momentIDs: ids, firstLabel: "12:30", lastLabel: "12:30") }

private func promise(_ id: String, _ sentence: String, to: String? = nil, speaker: String = "") -> Promise {
    Promise(id: id, chunkID: String(id.split(separator: "#")[0]), kind: .commitment, timeLabel: "12:30", wallStart: 0, sentence: sentence, toWhom: to, due: nil, context: nil, speakerId: speaker)
}

@MainActor
struct BriefingBuilderTests {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)
    private var today: String { DayID.today(now: now) }
    private var weekAgo: String { DayID.id(offset: -7, from: now) }

    private var chunks: [ChunkRecord] {
        [heard("old", "Priya booked the small hotel near the Alma district for the Lisbon trip in March.", day: weekAgo),
         heard("new", "Thanks Priya, which flights should we take for the trip?", day: today, at: 300)]
    }

    @Test func lastTimePrefersAnEarlierDayAndSaysHowLongAgo() {
        let b = BriefingBuilder.make(for: priya(["old", "new"]), chunks: chunks, promises: [], now: now)
        #expect(b.lastTime?.dayId == weekAgo && b.lastTime?.when == "A week ago")
        #expect(b.lastTime?.gist.contains("hotel") == true)
        #expect(b.moments == 2)
    }

    @Test func withOnlyTodayItFallsBackToToday() {
        let b = BriefingBuilder.make(for: priya(["new"]), chunks: chunks, promises: [], now: now)
        #expect(b.lastTime?.dayId == today)
    }

    @Test func whatYouOweThemIsThePromisesAboutThemThatAreNotDone() {
        let ps = [promise("a#0", "I will text you the link tomorrow.", to: "Priya"), promise("b#0", "I will call Priya's mother."),
                  promise("c#0", "I will pay the rent.", to: "Ravi"), promise("d#0", "I will book the flights.", to: "Priya")]
        let b = BriefingBuilder.make(for: priya(["old"]), chunks: chunks, promises: ps, done: ["d#0"], now: now)
        #expect(b.youOwe == ["I will text you the link tomorrow.", "I will call Priya's mother."])
    }

    @Test func onceYourVoiceIsKnownOnlyYourPromisesCountAsYoursAndTheirsComeFromTheirVoice() {
        let ps = [promise("a#0", "I will text you the link tomorrow.", to: "Priya", speaker: "me"),
                  promise("b#0", "I will send Priya the hotel details.", speaker: "priyavoice"),
                  promise("c#0", "I will tell Priya about the car.", speaker: "maya")]
        let b = BriefingBuilder.make(for: priya(["old"]), chunks: chunks, promises: ps, myVoice: "me", voiceNamed: { $0 == "Priya" ? "priyavoice" : nil }, now: now)
        #expect(b.youOwe == ["I will text you the link tomorrow."])
        #expect(b.theyOwe == ["I will send Priya the hotel details."])
    }

    @Test func topicsLeaveOutTheirNameAndAnEmptyBriefingIsEmpty() {
        let b = BriefingBuilder.make(for: priya(["old"]), chunks: chunks, promises: [], now: now)
        #expect(!b.topics.map { $0.lowercased() }.contains("priya") && b.topics.count <= 3)
        let nothing = BriefingBuilder.make(for: priya([]), chunks: chunks, promises: [], now: now)
        #expect(nothing.isEmpty && nothing.summary.isEmpty)
    }

    @Test func theSummaryIsOneReadableLine() {
        let ps = [promise("a#0", "I will text you the link tomorrow.", to: "Priya"), promise("b#0", "I will call Priya's mother.")]
        let s = BriefingBuilder.make(for: priya(["old"]), chunks: chunks, promises: ps, now: now).summary
        #expect(s.hasPrefix("Last time (a week ago): “") && s.contains("You owe them: I will text you the link tomorrow. (+1 more)"))
    }
}

@MainActor
struct BriefingPlannerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let people = [Person(name: "Priya", words: ["priya"], momentIDs: ["a", "b", "c"], firstLabel: "", lastLabel: ""),
                          Person(name: "Ravi", words: ["ravi"], momentIDs: ["d"], firstLabel: "", lastLabel: "")]
    private func briefing(_ p: Person) -> Briefing {
        Briefing(person: p.name, lastTime: .init(dayId: "x", when: "Yesterday", gist: "Planned the trip"), youOwe: [], theyOwe: [], topics: [], moments: 1)
    }

    @Test func aMeetingWithSomeoneEchoKnowsGetsABriefingFifteenMinutesBefore() {
        let start = now.addingTimeInterval(3 * 3_600)
        let plans = BriefingPlanner.plan(events: [CalendarEvent(id: "e1", title: "Lunch with Priya", start: start)], people: people, briefing: briefing, now: now)
        #expect(plans.count == 1 && plans[0].person == "Priya" && plans[0].fire == start.addingTimeInterval(-900))
        #expect(plans[0].title == "Before you see Priya" && plans[0].body.contains("Planned the trip"))
    }

    @Test func titleWordsMatchWithoutCaseAndFillerWordsDoNotCount() {
        let start = now.addingTimeInterval(7_200)
        func matches(_ title: String) -> Bool { !BriefingPlanner.plan(events: [CalendarEvent(id: "x", title: title, start: start)], people: people, briefing: briefing, now: now).isEmpty }
        #expect(matches("PRIYA / Ravi sync") && matches("Coffee with ravi") && matches("priya's birthday"))
        #expect(!matches("Team meeting") && !matches("Lunch with the family") && !matches(""))
    }

    @Test func eventsThatAreTooSoonAlreadyBegunOrSayNothingNewAreLeftOut() {
        let events = [CalendarEvent(id: "soon", title: "Call with Priya", start: now.addingTimeInterval(600)),
                      CalendarEvent(id: "begun", title: "Call with Priya", start: now.addingTimeInterval(-600)),
                      CalendarEvent(id: "ok", title: "Call with Priya", start: now.addingTimeInterval(7_200))]
        let plans = BriefingPlanner.plan(events: events, people: people, briefing: briefing, now: now)
        #expect(plans.map(\.eventID) == ["ok"], "10 minutes ahead is too soon for a 15 minute briefing")
        let empty = BriefingPlanner.plan(events: [events[2]], people: people, briefing: { Briefing(person: $0.name, lastTime: nil, youOwe: [], theyOwe: [], topics: [], moments: 0) }, now: now)
        #expect(empty.isEmpty, "nothing to say, so no notification")
    }

    @Test func whenTwoKnownPeopleAreInOneTitleTheOneHeardMostWins() {
        let e = CalendarEvent(id: "both", title: "Priya and Ravi dinner", start: now.addingTimeInterval(7_200))
        #expect(BriefingPlanner.plan(events: [e], people: people, briefing: briefing, now: now).map(\.person) == ["Priya"])
    }
}

@MainActor
struct BriefingCenterTests {
    private final class Reader: CalendarReading {
        var events: [CalendarEvent] = []
        func upcoming(hours: Int, now: Date) async -> [CalendarEvent] { events }
    }
    private final class Scheduler: NotificationScheduling {
        var allowed = true
        var added: [String] = []
        var removed: [String] = []
        func ensureAuthorized() async -> Bool { allowed }
        func add(id: String, title: String, body: String, at date: Date) async throws { added.append(id) }
        func remove(ids: [String]) { removed += ids }
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let people = [Person(name: "Priya", words: ["priya"], momentIDs: ["a"], firstLabel: "", lastLabel: "")]
    private func briefing(_ p: Person) -> Briefing { Briefing(person: p.name, lastTime: .init(dayId: "x", when: "Yesterday", gist: "Trip"), youOwe: [], theyOwe: [], topics: [], moments: 1) }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "echo-brief-\(UUID().uuidString)")! }

    @Test func offByDefaultAndNothingIsReadOrScheduledUntilTurnedOn() async {
        let reader = Reader(), sched = Scheduler()
        reader.events = [CalendarEvent(id: "e1", title: "Lunch with Priya", start: now.addingTimeInterval(7_200))]
        let c = BriefingCenter(reader: reader, scheduler: sched, defaults: defaults())
        #expect(!c.enabled)
        await c.refresh(people: people, briefing: briefing, now: now)
        #expect(sched.added.isEmpty && c.planned.isEmpty)
    }

    @Test func turnedOnItSchedulesAndAnotherRefreshReplacesWhatWasSetBefore() async {
        let reader = Reader(), sched = Scheduler()
        reader.events = [CalendarEvent(id: "e1", title: "Lunch with Priya", start: now.addingTimeInterval(7_200))]
        let d = defaults()
        let c = BriefingCenter(reader: reader, scheduler: sched, defaults: d)
        c.enabled = true
        await c.refresh(people: people, briefing: briefing, now: now)
        #expect(sched.added == ["echo.briefing.e1"] && c.planned.count == 1)
        reader.events = [CalendarEvent(id: "e2", title: "Call Priya", start: now.addingTimeInterval(9_000))]
        await c.refresh(people: people, briefing: briefing, now: now)
        #expect(sched.removed.contains("echo.briefing.e1"), "the old one is cleared first")
        #expect(sched.added == ["echo.briefing.e1", "echo.briefing.e2"] && c.planned.map(\.eventID) == ["e2"])
        #expect(BriefingCenter(reader: reader, scheduler: sched, defaults: d).enabled, "the choice is remembered")
    }

    @Test func withoutNotificationPermissionNothingIsSetAndTurningItOffClearsEverything() async {
        let reader = Reader(), sched = Scheduler()
        reader.events = [CalendarEvent(id: "e1", title: "Lunch with Priya", start: now.addingTimeInterval(7_200))]
        let c = BriefingCenter(reader: reader, scheduler: sched, defaults: defaults())
        c.enabled = true
        sched.allowed = false
        await c.refresh(people: people, briefing: briefing, now: now)
        #expect(sched.added.isEmpty)
        sched.allowed = true
        await c.refresh(people: people, briefing: briefing, now: now)
        #expect(sched.added.count == 1)
        c.enabled = false
        await c.refresh(people: people, briefing: briefing, now: now)
        #expect(c.planned.isEmpty && sched.removed.contains("echo.briefing.e1"))
        await c.refresh(people: people, briefing: briefing, now: now)
        c.clear()
        #expect(c.planned.isEmpty)
    }
}
