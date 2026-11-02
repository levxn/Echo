import Foundation
import Testing
@testable import Echo

private func line(_ id: String, _ text: String, day: String = DayID.today(), at wall: Double = 100, speaker: String = "") -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: .stored, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day, speakerId: speaker)
}

struct CalendarTitleTests {
    @Test func aPromiseBecomesATitleWithoutTheCueTheDuePhraseOrTheTag() {
        #expect(CalendarTitle.make(from: "I will send you the API specification by Wednesday noon that's a promise.", due: "By Wednesday noon") == "Send you the API specification")
        #expect(CalendarTitle.make(from: "I'll call Dr. Patel's office tomorrow morning.", due: "Tomorrow morning") == "Call Dr. Patel's office")
        #expect(CalendarTitle.make(from: "Remember to call grandma on Sunday.", due: "On Sunday") == "Call grandma")
        #expect(CalendarTitle.make(from: "I will order the book tonight and look up workshops this weekend.", due: "Tonight").hasPrefix("Order the book"))
    }

    @Test func longOnesAreShortenedAndEmptyOnesHaveAFallback() {
        let long = CalendarTitle.make(from: "I will " + String(repeating: "review the design document ", count: 6), due: nil)
        #expect(long.count <= 62 && long.hasSuffix("…"))
        #expect(CalendarTitle.make(from: "I will.", due: nil) == "Something you promised")
        #expect(CalendarTitle.make(from: "", due: nil) == "Something you promised")
    }
}

@MainActor
struct CalendarLinkTests {
    private final class Fake: CalendarWriting {
        var result = CalendarResult.added
        var events: [(title: String, notes: String, start: Date, minutes: Int)] = []
        func addEvent(title: String, notes: String, start: Date, minutes: Int) async -> CalendarResult {
            if result == .added { events.append((title, notes, start, minutes)) }
            return result
        }
    }

    private func promise(_ id: String = "c#0") -> Promise {
        Promise(id: id, chunkID: "c", kind: .commitment, timeLabel: "09:05", wallStart: 0, sentence: "I will send the spec by Friday.", toWhom: nil, due: "By Friday", context: nil)
    }

    @Test func anEventIsAddedWithTheTitleTheNotesAndHalfAnHour() async throws {
        let fake = Fake()
        let link = CalendarLink(calendar: fake, defaults: UserDefaults(suiteName: "echo-cal-\(UUID().uuidString)")!)
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(await link.add(promise(), at: when))
        let e = try #require(fake.events.first)
        #expect(e.title == "Send the spec" && e.start == when && e.minutes == 30 && e.notes.hasSuffix("From Echo") && e.notes.contains("I will send the spec"))
        #expect(link.date(for: "c#0") == when && link.problem == nil)
    }

    @Test func refusalsAreExplainedAndNothingIsRemembered() async {
        let fake = Fake()
        let link = CalendarLink(calendar: fake, defaults: UserDefaults(suiteName: "echo-cal2-\(UUID().uuidString)")!)
        fake.result = .denied
        #expect(await !link.add(promise(), at: Date()) && link.problem == .notAllowed && link.date(for: "c#0") == nil)
        #expect(CalendarLink.Problem.notAllowed.message.contains("Settings"))
        fake.result = .failed
        #expect(await !link.add(promise(), at: Date()) && link.problem == .failed)
    }

    @Test func whatWasAddedSurvivesARelaunchAndForgettingTheDayClearsIt() async {
        let d = UserDefaults(suiteName: "echo-cal3-\(UUID().uuidString)")!
        let first = CalendarLink(calendar: Fake(), defaults: d)
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        await first.add(promise(), at: when)
        let second = CalendarLink(calendar: Fake(), defaults: d)
        #expect(second.date(for: "c#0") == when)
        second.clear()
        #expect(second.date(for: "c#0") == nil && CalendarLink(calendar: Fake(), defaults: d).date(for: "c#0") == nil)
    }

    @Test func theChoicesAreTheDueTimeAndTomorrowMorningNeverInThePast() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let sunday = cal.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 17))!
        let withDue = ReminderOptions.calendarOptions(due: "Wednesday noon", now: sunday, calendar: cal)
        #expect(withDue.map(\.date) == [cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12))!, cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!])
        #expect(ReminderOptions.calendarOptions(due: nil, now: sunday, calendar: cal).count == 1)
        let same = ReminderOptions.calendarOptions(due: "Tomorrow morning", now: sunday, calendar: cal)
        #expect(same.count == 1, "tomorrow morning isn't offered twice")
    }
}

struct DecisionTests {
    @Test func decisionsAreFoundByTheWayPeopleSayThem() {
        let said = ["We decided to go with the second vendor.", "I've decided to take the job.", "Okay let's go with Friday then.",
                    "We agreed to split the cost.", "The decision is to wait until March.", "We're going with the blue one.",
                    "agreed we decided to go with the second vendor and Ravi will send the contract", "That's the final decision."]
        for (i, s) in said.enumerated() {
            #expect(DecisionExtractor.extract(from: [line("c\(i)", s)]).count == 1, "\(s)")
        }
    }

    @Test func promisesQuestionsAndIdleTalkAreNotDecisions() {
        for s in ["I will send the contract by Friday.", "What did we decide?", "Which vendor should we pick?", "We discussed the vendors.", "It is not decided yet."] {
            #expect(DecisionExtractor.extract(from: [line("x", s)]).isEmpty || s == "What did we decide?", "\(s)")
        }
    }

    @Test func eachCarriesItsSentenceDayAndWhatWasAskedJustBefore() throws {
        let chunks = [line("a", "We need to pick a vendor. Ravi, what did you find?", day: "2026-10-26", at: 100, speaker: "maya"),
                      line("b", "Agreed we decided to go with the second vendor", day: "2026-10-26", at: 130, speaker: "maya"),
                      line("c", "We decided to wait.", day: "2026-11-02", at: 100)]
        let found = DecisionExtractor.extract(from: chunks, now: Date(timeIntervalSince1970: 1_793_000_000))
        #expect(found.map(\.chunkID) == ["b", "c"], "oldest first")
        let b = try #require(found.first)
        #expect(b.sentence == "Agreed we decided to go with the second vendor." && b.speakerId == "maya")
        #expect(b.context?.contains("pick a vendor") == true)
        #expect(found[1].context == nil, "nothing was said just before it that day")
        #expect(b.timeLabel != found[1].timeLabel || b.dayId != found[1].dayId)
    }

    @Test func whyDidWeAreRoutedToMuseButOrdinaryLookupsAreNot() {
        let none = RetrievalOutcome(query: "", knownTerms: [], unknownTerms: [], timeWindow: nil, hits: [], coverage: 0, headlineWeights: [:], corpusSize: 0, elapsedMs: 0)
        let why = Router.route(query: "Why did we pick the second vendor?", outcome: none)
        #expect(why.tier == .cloud && why.intent == .general)
        let summary = Router.route(query: "Summarize why we decided on the second vendor", outcome: none)
        #expect(summary.intent == .summary, "an explicit recap is still a recap")
    }
}
