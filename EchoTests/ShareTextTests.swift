import Foundation
import Testing
@testable import Echo

struct ShareTextTests {
    @Test func anItemReadsAsOneLine() {
        #expect(ShareText.item(title: "Send the spec", detail: "To Ravi", when: "Wednesday noon", time: "09:05")
                == "• Send the spec (To Ravi, Wednesday noon) at 09:05")
        #expect(ShareText.item(title: "Call the dentist", detail: "", when: "", time: "") == "• Call the dentist")
        #expect(ShareText.item(title: "Pay rent", detail: "", when: "Friday", time: "") == "• Pay rent (Friday)")
    }

    @Test func anAnswerKeepsTheQuestionTheAnswerAndTheLines() {
        let text = ShareText.answer(question: "What did I promise?", answer: "Two things.", lines: ["• One", "• Two"])
        #expect(text == "Q: What did I promise?\n\nA: Two things.\n\n• One\n• Two\n\nShared from Echo")
        #expect(ShareText.answer(question: "Q?", answer: "A.") == "Q: Q?\n\nA: A.\n\nShared from Echo", "no empty gap without lines")
    }

    @Test func theDaySummaryListsActionsAndPeopleOnlyWhenThereAreSome() {
        let full = ShareText.digest(summary: "A busy day.", actions: [("Send the spec", "Ravi", "Wednesday", "09:05")], people: ["Priya", "Ravi"])
        #expect(full.hasPrefix("My day, summarized by Muse\n\nA busy day.\n\nAction items\n• Send the spec (Ravi, Wednesday) at 09:05"))
        #expect(full.hasSuffix("People: Priya, Ravi\n\nShared from Echo"))
        let bare = ShareText.digest(summary: "Quiet.", actions: [], people: [])
        #expect(bare == "My day, summarized by Muse\n\nQuiet.\n\nShared from Echo")
    }
}
