import Foundation
import Testing
@testable import Echo

private let calendarUTC: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
/// Monday 2 November 2026, 10:00 (UTC): the day the demo recording is "from".
private let monday = calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!

private func chunk(_ id: String, _ text: String, at wall: Double, speaker: String = "", day: String = "2026-11-02") -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a", status: .stored,
                speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day, speakerId: speaker)
}

private func extract(_ chunks: [ChunkRecord], me: String? = nil, names: [String: String] = [:]) -> [ActionItem] {
    ActionExtractor.extract(from: chunks, userName: "Levin", myVoice: me, voiceName: { names[$0] }, now: monday, calendar: calendarUTC)
}

/// A line each, a minute apart, so they form one conversation.
private func talk(_ lines: [(String, String)]) -> [ChunkRecord] {
    lines.enumerated().map { chunk("c\($0.offset)", $0.element.1, at: 36_000 + Double($0.offset) * 20, speaker: $0.element.0) }
}

struct ActionExtractorTests {
    private func one(_ text: String, me: String? = nil, speaker: String = "") -> [ActionItem] { extract([chunk("c", text, at: 36_000, speaker: speaker)], me: me) }

    // MARK: Kinds

    @Test func aDocumentToSendIsAnEmail() throws {
        let a = try #require(one("Right I will send you the API specification by Wednesday noon that's a promise").first)
        #expect(a.kind == .email && a.title == "Send the API specification", "\(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12)) && a.dueText == "Wednesday noon")
        #expect(a.quote.contains("API specification"))
    }

    @Test func aLinkOrRecipeToSendIsAMessage() throws {
        let a = try #require(one("I will send the lentil soup recipe this evening I promise").first)
        #expect(a.kind == .message && a.title == "Send the lentil soup recipe", "\(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 18)))
        let b = try #require(one("I will text you the link if you want to join").first)
        #expect(b.kind == .message && b.title.hasPrefix("Text the link"), "\(b.title)")
        let c = try #require(one("I will give you a final answer before November 20").first)
        #expect(c.kind == .message && c.dueText == "November 20", "\(c.kind) \(c.dueText ?? "")")
    }

    @Test func aCallNamesWhoToCall() throws {
        let a = try #require(one("Remember to call grandma on Sunday she has been asking about you").first)
        #expect(a.kind == .call && a.title == "Call Grandma" && a.person == "Grandma", "\(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 9)))
        let b = try #require(one("I will call grandmother this Sunday afternoon I promise").first)
        #expect(b.title == "Call Grandma" && b.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 15)))
    }

    @Test func herOfficeMeansTheDoctorJustMentioned() throws {
        let chunks = talk([("P", "Also you mentioned your tooth was bothering you. See Doctor Patel, she is excellent."),
                           ("L", "Thanks I will call her office tomorrow morning and book an appointment")])
        let a = try #require(extract(chunks).first { $0.kind == .call })
        #expect(a.title.contains("Patel") && a.title.hasPrefix("Call"), "\(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9)))
    }

    @Test func anEventWithAClockTimeIsACalendarEntry() throws {
        let a = try #require(one("Yes I received your photos. I have booked a plumber to come on Friday at 10 in the morning.").first)
        #expect(a.kind == .calendar && a.title == "Plumber visit" && a.hasClock && !a.allDay, "\(a.kind) \(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 10)) && a.dueText == "Friday at 10 in the morning")
    }

    @Test func aBirthdayIsAnAllDayEventThatRepeats() throws {
        let a = try #require(one("Your mother's birthday is on November 14 and I want to take her to the lake cabin for the weekend").first)
        #expect(a.kind == .calendar && a.allDay && a.repeatsYearly && a.title.lowercased().contains("birthday"), "\(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9)))
    }

    @Test func aDeployOnAMorningIsAnEvent() throws {
        let a = try #require(one("I think we can deploy a production on Thursday morning").first)
        #expect(a.kind == .calendar && a.title.hasPrefix("Deploy"), "\(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))
    }

    @Test func aSpokenListBecomesOneShoppingListAndThePickUpGivesItATime() throws {
        let chunks = talk([("M", "We also need groceries eggs, olive oil, and oranges for the juice"),
                           ("L", "I will pick those up on my way home from work tomorrow")])
        let items = extract(chunks)
        let list = try #require(items.first { $0.kind == .shopping })
        #expect(list.items == ["Eggs", "Olive oil", "Oranges"], "\(list.items)")
        #expect(list.dueText == "tomorrow" && list.due != nil, "the pick-up time is on the list")
        #expect(!items.contains { $0.kind == .todo && $0.title.lowercased().contains("pick those up") }, "not also a separate to-do: \(items.map(\.title))")
    }

    @Test func aRequestToYouIsAToDoWithWhoAsked() throws {
        let a = try #require(one("Dinner is ready everyone can you bring the salad, sweetheart?", speaker: "M").first)
        #expect(a.kind == .todo && a.title == "Bring the salad" && a.detail.hasPrefix("Asked by"), "\(a.title) | \(a.detail)")
        #expect(extract([chunk("c", "Can you send me the report", at: 36_000, speaker: "L")], me: "L").first?.kind == .waiting, "when I ask someone, I am waiting on them")
    }

    @Test func otherPeoplesPromisesAreWaitingOn() throws {
        let chunks = [chunk("a", "Great I will review the design document on Tuesday and leave comments before the end of the day", at: 36_000, speaker: "M"),
                       chunk("b", "Right I will send you the API specification by Wednesday noon", at: 36_020, speaker: "L")]
        let items = extract(chunks, me: "L", names: ["M": "Maya"])
        let waiting = try #require(items.first { $0.kind == .waiting })
        #expect(waiting.person == "Maya" && waiting.title.hasPrefix("Review the design document") && waiting.detail == "Maya said they would", "\(waiting.title) | \(waiting.detail)")
        #expect(waiting.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 9)))
        #expect(items.first { $0.kind == .email }?.title.hasPrefix("Send the API specification") == true, "my own promise is still mine")
        // before the person has said which voice is theirs, everything is theirs
        #expect(extract(chunks).allSatisfy { $0.kind != .waiting })
    }

    @Test func twoPromisesWithTheirOwnTimesBecomeTwoActions() {
        let items = one("Oh that's good I will order the book tonight and look at workshop this weekend")
        #expect(items.count == 2, "\(items.map(\.title))")
        #expect(items.first?.title.lowercased().hasPrefix("order") == true && items.last?.title.lowercased().hasPrefix("look") == true)
        #expect(items.first?.dueText == "tonight" && items.last?.dueText == "this weekend")
    }

    @Test func aMessageNamesWhoItIsForWhenTheWearerAddressedThemJustBefore() throws {
        let chunks = talk([("P", "I finally booked the trip. A small place near the Alma district."),
                           ("L", "That sounds amazing Priya. Which hotel did you pick?"),
                           ("P", "Also what are you getting your mom for her birthday?"),
                           ("L", "I will send the lentil soup recipe this evening I promise")])
        let a = try #require(extract(chunks, me: "L").first { $0.kind == .message })
        #expect(a.person == "Priya" && a.detail == "To Priya" && a.title == "Send the lentil soup recipe to Priya", "\(a.title) | \(a.detail)")
    }

    // MARK: When

    @Test func relativeDaysCountFromTheDayTheyWereSaid() throws {
        let lastWeek = chunk("old", "I will transfer it tomorrow first thing", at: 36_000, day: "2026-10-26")
        let a = try #require(extract([lastWeek]).first)
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 8)))
        #expect(a.dayId == "2026-10-26")
    }

    @Test func aPastCalendarEventIsStaleButAnOverdueToDoIsNot() {
        var event = ActionItem(id: "e", kind: .calendar, title: "Plumber visit", quote: "", chunkID: "c", dayId: "2026-10-26", wallStart: 0, timeLabel: "09:00")
        event.due = calendarUTC.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 10))
        #expect(event.isStale(now: monday))
        var todo = event; todo.kind = .todo
        #expect(!todo.isStale(now: monday))
        var future = event; future.due = calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 10))
        #expect(!future.isStale(now: monday))
    }

    // MARK: Not actions

    @Test(arguments: [
        "Okay let's start. Where are we on the billing service?", "That sounds amazing. Which hotel did you pick?", "Thanks everyone same time tomorrow",
        "Four percent is a bit more than I expected can I think about it and let you know", "I was thinking of a book about pottery she has been wanting to take a class",
        "Lovely idea pair it with a voucher for a beginner workshop", "Sure mom smells fantastic", "Alright let's eat before it gets cold",
    ])
    func ordinaryTalkIsNotAnAction(_ text: String) {
        #expect(one(text).isEmpty, "\(text) → \(one(text).map(\.title))")
    }

    @Test func idsAreStableAndEachActionKeepsItsSource() throws {
        let c = chunk("abc", "Right I will send you the API specification by Wednesday noon that's a promise", at: 36_000, speaker: "L")
        let first = extract([c], me: "L"), again = extract([c], me: "L")
        #expect(first.map(\.id) == again.map(\.id) && first.first?.id == "abc#a0")
        #expect(first.first?.chunkID == "abc" && first.first?.speakerId == "L" && first.first?.dayId == "2026-11-02")
    }

    @Test func aSlotOfferedForSomethingBeingArrangedIsAnAppointment() throws {
        let a = try #require(one("It needs a filling. I can do it next Tuesday at three in the afternoon.").first)
        #expect(a.kind == .calendar && a.title == "Appointment" && a.hasClock, "\(a.kind) \(a.title)")
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15)))
    }

    @Test func todayWithNoTimeMeansByTheEndOfTheDay() throws {
        let a = try #require(one("I will send you the booking confirmation today.", me: "L", speaker: "L").first)
        #expect(a.due == calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 17)), "\(String(describing: a.due))")
    }
}

