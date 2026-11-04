import Foundation
import Testing
@testable import Echo

struct EventTimeTests {
    private static var calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    /// Monday 2 November 2026, 10:00.
    private let monday = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 2, hour: 10))!

    private func find(_ text: String, from reference: Date? = nil) -> EventWhen? {
        EventTime.find(in: text, reference: reference ?? monday, calendar: Self.calendar)
    }

    @Test(arguments: [
        ("a plumber to come on Friday at 10 in the morning", 2026, 11, 6, 10, 0, true),
        ("I think we can deploy on Thursday morning", 2026, 11, 5, 9, 0, false),
        ("I will send it by Wednesday noon", 2026, 11, 4, 12, 0, true),
        ("a final answer before November 20", 2026, 11, 20, 9, 0, false),
        ("your mother's birthday is on November fourteenth", 2026, 11, 14, 9, 0, false),
        ("on the 20th of November", 2026, 11, 20, 9, 0, false),
        ("I will transfer it tomorrow first thing", 2026, 11, 3, 8, 0, false),
        ("I can do it next Tuesday at three in the afternoon", 2026, 11, 10, 15, 0, true),
        ("see you this Sunday afternoon", 2026, 11, 8, 15, 0, false),
        ("the meeting is tomorrow at 3 pm", 2026, 11, 3, 15, 0, true),
        ("let's meet tomorrow at 10:30 am", 2026, 11, 3, 10, 30, true),
        ("dinner on Saturday at 8 in the evening", 2026, 11, 7, 20, 0, true),
        ("call her office tomorrow morning", 2026, 11, 3, 9, 0, false),
        ("I will order the book tonight", 2026, 11, 2, 20, 0, false),
    ])
    func thePhrasesTheRecognizerWrites(_ text: String, _ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ clock: Bool) throws {
        let when = try #require(find(text), "no time found in: \(text)")
        #expect(when.date == date(y, m, d, h, min), "\(text) → \(when.date)")
        #expect(when.hasClock == clock, "\(text)")
    }

    @Test func clockTimesWithoutADayBelongToTheDayTheyWereSaid() throws {
        #expect(try #require(find("the meeting is at three")).date == date(2026, 11, 2, 15))
        #expect(try #require(find("we start at 10")).date == date(2026, 11, 2, 10))
        #expect(try #require(find("at 9:15 sharp")).date == date(2026, 11, 2, 9, 15))
    }

    @Test func theWordsOfTheTimeAreKeptForTheCard() throws {
        #expect(try #require(find("a plumber to come on Friday at 10 in the morning please")).phrase == "Friday at 10 in the morning")
        #expect(try #require(find("deploy on Thursday morning")).phrase == "Thursday morning")
        #expect(try #require(find("before November 20 please")).phrase == "November 20")
    }

    @Test func relativeDaysAreCountedFromWhenTheyWereSaidNotFromNow() throws {
        let lastWeek = date(2026, 10, 26, 12)
        #expect(try #require(find("I will pay it tomorrow morning", from: lastWeek)).date == date(2026, 10, 27, 9))
        #expect(try #require(find("see you on Friday", from: lastWeek)).date == date(2026, 10, 30, 9))
    }

    @Test func aDateAlreadyPastThisYearMeansNextYear() throws {
        let december = date(2026, 12, 20, 12)
        #expect(try #require(find("her birthday is on November 5", from: december)).date == date(2027, 11, 5, 9))
    }

    @Test(arguments: ["I will do it", "That sounds amazing", "It is about 5 percent more", "at 5 percent interest", "we are 3 people", "The pin is 4821"])
    func sentencesWithoutATimeHaveNone(_ text: String) {
        #expect(find(text) == nil, "found a time in: \(text)")
    }

    @Test func sevenToElevenWithNoPeriodReadAsMorningAndOneToSixAsAfternoon() {
        #expect(EventTime.clock(in: "at 8")?.hour == 8 && EventTime.clock(in: "at 11")?.hour == 11)
        #expect(EventTime.clock(in: "at 2")?.hour == 14 && EventTime.clock(in: "at 6")?.hour == 18)
        #expect(EventTime.clock(in: "at 12")?.hour == 12 && EventTime.clock(in: "at 12 am")?.hour == 0)
        #expect(EventTime.clock(in: "at 10 in the morning")?.hour == 10 && EventTime.clock(in: "at 7 in the evening")?.hour == 19)
    }
}
