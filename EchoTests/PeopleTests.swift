import Foundation
import Testing
@testable import Echo

@MainActor
struct PeopleTests {
    private func chunk(_ id: String, _ t: Double, _ text: String) -> ChunkRecord {
        ChunkRecord(id: id, index: 0, wallStart: t, fileOffset: 0, duration: 5, peakDb: -10, meanDb: -20, audioFile: "x.m4a",
                    status: .stored, speechConfidence: 1, confirmedSeconds: 5, transcript: text)
    }

    @Test func theDemoDayListsThePeopleItMentions() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let people = PeopleIndex.build(from: h.chunks)
        let names = people.map { $0.name.lowercased() }
        for expected in ["priya", "brennan", "patel"] { #expect(names.contains { $0.contains(expected) }, "\(expected) in \(names)") }
        #expect(people.allSatisfy { $0.count >= 1 && !$0.momentIDs.isEmpty })
        #expect(people == people.sorted { $0.count != $1.count ? $0.count > $1.count : $0.firstLabel < $1.firstLabel }, "most-mentioned first")
        #expect(!names.contains("lisbon") && !names.contains("monday") && !names.contains("march"), "places and dates are not people: \(names)")
    }

    @Test func theWearerIsNotListedAmongThePeopleTheyTalkedTo() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let everyone = PeopleIndex.build(from: h.chunks).map { $0.name.lowercased() }
        let without = PeopleIndex.build(from: h.chunks, userName: "Priya").map { $0.name.lowercased() }
        #expect(everyone.contains { $0.contains("priya") })
        #expect(!without.contains { $0.contains("priya") })
        #expect(without.count == everyone.count - 1)
    }

    @Test func aTitleIsNotPartOfTheNameAndPossessivesStillCount() {
        let chunks = [chunk("a", 100, "Please call Doctor Patel tomorrow morning."),
                      chunk("b", 200, "I think Patel's office opens at nine."),
                      chunk("c", 300, "We had pasta for lunch.")]
        let people = PeopleIndex.build(from: chunks)
        let patel = people.first { $0.words.contains("patel") }
        #expect(patel?.momentIDs == ["a", "b"])
        #expect(patel?.words.contains("doctor") == false)
        #expect(patel?.firstLabel == chunks[0].wallLabel && patel?.lastLabel == chunks[1].wallLabel)
    }

    @Test func aDayWithNoNamesIsEmptyAndOnlyStoredMomentsCount() {
        #expect(PeopleIndex.build(from: [chunk("a", 1, "we had pasta for lunch today")]).isEmpty)
        #expect(PeopleIndex.build(from: []).isEmpty)
        var dropped = chunk("d", 5, "Please call Doctor Patel tomorrow morning.")
        dropped.status = .dropped
        #expect(PeopleIndex.build(from: [dropped]).isEmpty)
    }

    @Test func wordsAreLowercasedWithPossessivesRemoved() {
        #expect(PeopleIndex.words(in: "Priya's trip, Patel’s office; ok") == ["priya", "trip", "patel", "office", "ok"])
    }

    @Test func aPersonsCommitmentsAreTheOnesSaidToThemOrAboutThem() {
        func promise(_ sentence: String, to: String?) -> Promise {
            Promise(id: sentence, chunkID: "c", kind: .commitment, timeLabel: "09:05", wallStart: 0, sentence: sentence, toWhom: to, due: nil, context: nil)
        }
        let priya = Person(name: "Priya", words: ["priya"], momentIDs: ["c"], firstLabel: "09:05", lastLabel: "09:05")
        let list = [promise("I will text you the link.", to: "Priya"), promise("I will call Priya's mother.", to: nil), promise("I will pay the rent.", to: "Ravi")]
        #expect(PeopleIndex.promises(for: priya, in: list).map(\.sentence) == ["I will text you the link.", "I will call Priya's mother."])
    }

    @Test func peopleTheWearerHidesStayHiddenAndOthersRemain() {
        let a = Person(name: "Lee", words: ["lee"], momentIDs: ["c"], firstLabel: "12:30", lastLabel: "12:30")
        let b = Person(name: "Priya", words: ["priya"], momentIDs: ["c"], firstLabel: "12:30", lastLabel: "12:30")
        #expect(PeopleIgnore.visible([a, b], ignoring: "").map(\.name) == ["Lee", "Priya"])
        let raw = PeopleIgnore.raw(adding: a.id, to: "")
        #expect(PeopleIgnore.visible([a, b], ignoring: raw).map(\.name) == ["Priya"])
        #expect(PeopleIgnore.raw(adding: a.id, to: raw) == raw, "hiding twice changes nothing")
        #expect(PeopleIgnore.ids(from: PeopleIgnore.raw(adding: b.id, to: raw)) == [a.id, b.id])
    }
}
