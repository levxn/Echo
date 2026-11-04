import CoreGraphics
import Testing
@testable import Echo

struct ComponentsTests {
    private func sizes(_ widths: [CGFloat], height: CGFloat = 20) -> [CGSize] { widths.map { CGSize(width: $0, height: height) } }

    @Test func itemsThatFitStayOnOneLine() {
        let r = FlowLayout.arrange(sizes: sizes([50, 60, 40]), maxWidth: 300, spacing: 6, lineSpacing: 6)
        #expect(r.positions == [CGPoint(x: 0, y: 0), CGPoint(x: 56, y: 0), CGPoint(x: 122, y: 0)])
        #expect(r.size == CGSize(width: 162, height: 20))
    }

    @Test func anItemThatDoesNotFitStartsANewLine() {
        let r = FlowLayout.arrange(sizes: sizes([100, 100, 100]), maxWidth: 230, spacing: 6, lineSpacing: 8)
        #expect(r.positions == [CGPoint(x: 0, y: 0), CGPoint(x: 106, y: 0), CGPoint(x: 0, y: 28)])
        #expect(r.size.height == 48)
    }

    @Test func aTooWideItemSitsAloneAndNothingIsLost() {
        let r = FlowLayout.arrange(sizes: sizes([40, 500, 40]), maxWidth: 200, spacing: 6, lineSpacing: 6)
        #expect(r.positions.count == 3)
        #expect(r.positions[1] == CGPoint(x: 0, y: 26), "the wide one starts its own line")
        #expect(r.positions[2] == CGPoint(x: 0, y: 52), "and the next one wraps below it")
        #expect(r.size.width <= 200)
    }

    @Test func aLineIsAsTallAsItsTallestItem() {
        let r = FlowLayout.arrange(sizes: [CGSize(width: 50, height: 20), CGSize(width: 50, height: 44), CGSize(width: 200, height: 20)],
                                   maxWidth: 150, spacing: 6, lineSpacing: 6)
        #expect(r.positions[2] == CGPoint(x: 0, y: 50))
    }

    @Test func noItemsTakeNoSpace() {
        #expect(FlowLayout.arrange(sizes: [], maxWidth: 100, spacing: 6, lineSpacing: 6).size == .zero)
    }

    @Test func durationsAreSpokenInWords() {
        #expect(Format.spoken(233) == "3 minutes 53 seconds")
        #expect(Format.spoken(60) == "1 minute")
        #expect(Format.spoken(61) == "1 minute 1 second")
        #expect(Format.spoken(45) == "45 seconds")
        #expect(Format.spoken(0) == "0 seconds")
        #expect(Format.spoken(-5) == "0 seconds")
    }
}

struct TodaySectionTests {
    @Test func theSegmentsAreNamedForWhatTheyShow() {
        #expect(TodaySection.allCases.map(\.label) == ["Summary", "Promises", "People", "Timeline"])
    }

    @Test func eachBadgeIsTheNumberItsNameImplies() {
        func count(_ s: TodaySection, open: Int = 15, people: Int = 6, talks: Int = 4) -> Int? { s.count(openPromises: open, people: people, conversations: talks) }
        #expect(count(.summary) == nil, "a summary has nothing to count")
        #expect(count(.commitments) == 15 && count(.people) == 6 && count(.day) == 4)
        #expect(count(.commitments, open: 0) == nil && count(.people, people: 0) == nil && count(.day, talks: 0) == nil, "no badge when there is nothing")
    }

    @Test func voiceOverHearsWhatTheBadgeMeans() {
        func spoken(_ s: TodaySection, open: Int = 15, people: Int = 6, talks: Int = 4) -> String? { s.spokenCount(openPromises: open, people: people, conversations: talks) }
        #expect(spoken(.commitments) == "15 open" && spoken(.people) == "6 mentioned" && spoken(.day) == "4 conversations")
        #expect(spoken(.day, talks: 1) == "1 conversation")
        #expect(spoken(.summary) == nil && spoken(.commitments, open: 0) == nil)
    }

    @Test func launchArgumentsPickTheOpeningSection() {
        #expect(TodaySection.initial(arguments: []) == .summary)
        #expect(TodaySection.initial(arguments: ["-today-section", "day"]) == .day)
        #expect(TodaySection.initial(arguments: ["-today-section", "commitments"]) == .commitments)
        #expect(TodaySection.initial(arguments: ["-today-focus", "promises"]) == .commitments, "the older hook still opens Commitments")
        #expect(TodaySection.initial(arguments: ["-today-section", "nonsense"]) == .summary)
        #expect(TodaySection.initial(arguments: ["-today-section"]) == .summary, "a missing value is ignored")
        #expect(TodaySection.initial(arguments: ["-today-section", "day", "-today-focus", "promises"]) == .day, "the explicit section wins")
    }

    @Test func everySectionHasADistinctID() {
        #expect(Set(TodaySection.allCases.map(\.id)).count == TodaySection.allCases.count)
    }
}

struct CappedListTests {
    @Test func aLongListShowsTheFirstFewUntilExpanded() {
        let items = Array(1...9)
        #expect(Capped.visible(items, limit: 5, showAll: false) == [1, 2, 3, 4, 5])
        #expect(Capped.visible(items, limit: 5, showAll: true) == items)
    }

    @Test func aShortListIsNeverCutOrPadded() {
        #expect(Capped.visible([1, 2, 3], limit: 5, showAll: false) == [1, 2, 3])
        #expect(Capped.visible([Int](), limit: 5, showAll: false).isEmpty)
        #expect(Capped.visible([1, 2, 3, 4, 5], limit: 5, showAll: false).count == 5, "exactly the limit needs no Show all")
    }

    @Test func theYouTabShowsThreeSentRequestsByDefault() {
        #expect(YouView.activityLimit == 3)
    }
}
