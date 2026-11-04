import Foundation
import Testing
@testable import Echo

/// The demo day exactly as the phone transcribed it (no punctuation, digits for numbers, the occasional mishearing), with each moment
/// attributed to the person the script says spoke it. These are the actions a person would expect to find on their Actions page.
@MainActor
struct ActionDemoDayTests {
    private let calendarUTC: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()

    private func actions() async throws -> (items: [ActionItem], cleanup: () -> Void) {
        let h = try await Harness.make()
        var speaker: [String: String] = [:]
        for (s, scene) in h.manifest.scenes.enumerated() { for (l, line) in scene.lines.enumerated() { for id in h.chunkIDs(forLines: [(s, l)]) { speaker[id] = line.speaker } } }
        var chunks = h.chunks
        for i in chunks.indices { chunks[i].speakerId = speaker[chunks[i].id] ?? ""; chunks[i].dayId = "2026-11-02" }
        let now = calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))!
        let items = ActionExtractor.extract(from: chunks, userName: "Levin", myVoice: "Levin", voiceName: { $0 }, now: now, calendar: calendarUTC)
        return (items, h.cleanup)
    }

    private func date(_ d: Int, _ h: Int, month: Int = 11) -> Date { calendarUTC.date(from: DateComponents(year: 2026, month: month, day: d, hour: h))! }

    @Test func theDemoDayGivesTheActionsAPersonWouldExpect() async throws {
        let (items, cleanup) = try await actions()
        defer { cleanup() }
        func find(_ kind: ActionKind, _ words: String) -> ActionItem? { items.first { $0.kind == kind && $0.title.lowercased().contains(words.lowercased()) } }

        let spec = try #require(find(.email, "API specification"), "\(items.map(\.title))")
        #expect(spec.due == date(4, 12) && spec.person == "Ravi" && spec.title == "Send the API specification to Ravi")
        let recipe = try #require(find(.message, "lentil soup recipe"))
        #expect(recipe.person == "Priya" && recipe.due == date(2, 18) && recipe.detail.contains("asked by Priya"), "\(recipe.detail)")
        let answer = try #require(find(.message, "final answer"))
        #expect(answer.due == date(20, 9) && answer.person == "Brennan")

        let doctor = try #require(items.first { $0.kind == .call && $0.title.contains("Patel") }, "\(items.map(\.title))")
        #expect(doctor.due == date(3, 9))
        let grandma = items.filter { $0.title == "Call Grandma" }
        #expect(grandma.count == 1 && grandma[0].due == date(8, 15), "one action for grandma, at the time the wearer promised: \(grandma.map(\.detail))")

        let plumber = try #require(find(.calendar, "Plumber"))
        #expect(plumber.due == date(6, 10) && plumber.hasClock && plumber.dueText == "Friday at 10 in the morning")
        let birthday = try #require(find(.calendar, "birthday"))
        #expect(birthday.allDay && birthday.repeatsYearly && birthday.due == date(14, 9))
        #expect(find(.calendar, "Deploy")?.due == date(5, 9))

        let list = try #require(items.first { $0.kind == .shopping })
        #expect(list.items == ["Eggs", "Olive oil", "Oranges"] && list.due == date(3, 9))

        #expect(find(.todo, "Order the book")?.due == date(2, 20) && find(.todo, "Look at workshop")?.due == date(7, 9))
        #expect(find(.todo, "Transfer it")?.detail.contains("rent for this month") == true, "the card says what \"it\" is")
        #expect(find(.todo, "Bring the salad")?.detail == "Asked by Mom")
    }

    @Test func otherPeoplesPromisesAreWaitingOnAndNothingIsDoubled() async throws {
        let (items, cleanup) = try await actions()
        defer { cleanup() }
        let waiting = items.filter { $0.kind == .waiting }
        #expect(Set(waiting.map(\.person)) == ["Maya", "Ravi", "Priya"], "\(waiting.map { ($0.person ?? "?") + ": " + $0.title })")
        #expect(waiting.first { $0.person == "Maya" }?.due == date(3, 9))
        #expect(waiting.first { $0.person == "Priya" }?.title == "Text the link", "\(waiting.first { $0.person == "Priya" }?.title ?? "")")
        #expect(!items.contains { $0.title == "Send it" }, "a bare 'send it' is not an action")
        #expect(items.filter { $0.title.lowercased().contains("lentil") }.count == 1, "the reminder and the promise are one action")
    }

    @Test func eachActionPointsBackToItsMomentAndIdsAreUnique() async throws {
        let (items, cleanup) = try await actions()
        defer { cleanup() }
        #expect(Set(items.map(\.id)).count == items.count)
        #expect(items.allSatisfy { !$0.quote.isEmpty && !$0.chunkID.isEmpty && !$0.title.isEmpty })
        #expect((12...22).contains(items.count), "\(items.count) actions: \(items.map(\.title))")
    }

    @Test func noFillerBecomesAnAction() async throws {
        let (items, cleanup) = try await actions()
        defer { cleanup() }
        let titles = items.map { $0.title.lowercased() }
        for filler in ["billing service", "sounds amazing", "same time tomorrow", "smells fantastic", "before it gets cold", "hotel"] {
            #expect(!titles.contains { $0.contains(filler) }, "\(filler) became an action: \(titles)")
        }
    }
}
