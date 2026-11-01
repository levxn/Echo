import Foundation
import Testing
@testable import Echo

/// Commitments are found on the phone with rules, so they are checked against the scripted day: the manifest
/// says which lines contain a promise, and the real ASR transcripts say how well the rules cope with them.
@MainActor
struct PromiseTests {
    private static let commitmentLine = try! NSRegularExpression(pattern: #"\bI will\b|\bI'll\b|\bI promise\b"#)
    private static let reminderLine = try! NSRegularExpression(pattern: #"\bremember to\b|\bdon't forget\b"#, options: .caseInsensitive)

    private func scriptedLines(matching regex: NSRegularExpression, in h: Harness) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        for (s, scene) in h.manifest.scenes.enumerated() {
            for (l, line) in scene.lines.enumerated()
            where regex.firstMatch(in: line.text, range: NSRange(line.text.startIndex..., in: line.text)) != nil {
                out.append((s, l))
            }
        }
        return out
    }

    @Test func findsTheScriptedPromisesAndNothingElse() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let found = PromiseExtractor.extract(from: h.chunks)
        let foundChunks = Set(found.map(\.chunkID))

        let promiseLines = scriptedLines(matching: Self.commitmentLine, in: h)
        let reminderLines = scriptedLines(matching: Self.reminderLine, in: h)
        #expect(promiseLines.count >= 12, "the script should contain a dozen or more promises")

        // Recall: the recognizer garbles a line or two ("I will add a compatibility layer"), so allow a little slack.
        let recalled = promiseLines.filter { !h.chunkIDs(forLines: [$0]).isDisjoint(with: foundChunks) }
        #expect(recalled.count >= promiseLines.count - 2, "found \(recalled.count) of \(promiseLines.count) scripted promises")

        // Precision: everything listed comes from a scripted promise or reminder line.
        let allowed = h.chunkIDs(forLines: promiseLines + reminderLines)
        let stray = found.filter { !allowed.contains($0.chunkID) }
        #expect(stray.isEmpty, "unexpected: \(stray.map(\.sentence))")
    }

    @Test func readsWhenSomethingIsDue() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let found = PromiseExtractor.extract(from: h.chunks)
        func due(_ needle: String) -> String? {
            found.first { $0.sentence.lowercased().contains(needle) }?.due?.lowercased()
        }
        #expect(due("api specification") == "by wednesday noon")
        #expect(due("call her office") == "tomorrow morning")
        #expect(due("lentil soup recipe") == "this evening")
        #expect(due("final answer") == "before november 20")
        #expect(due("transfer it") == "tomorrow first thing")
        #expect(due("review the design") == "on tuesday")
    }

    @Test func aClauseStartsAtTheCueNotAtTheFiller() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let found = PromiseExtractor.extract(from: h.chunks)
        let spec = try #require(found.first { $0.sentence.lowercased().contains("api specification") })
        #expect(spec.sentence.hasPrefix("I will send you"), "got: \(spec.sentence)")
        #expect(spec.kind == .commitment)
        #expect(!found.contains { $0.sentence.lowercased().contains("still need") }, "a need is not a promise")
    }

    @Test func remindersAreMarkedAndHaveNoRecipient() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let found = PromiseExtractor.extract(from: h.chunks)
        let reminder = try #require(found.first { $0.kind == .reminder && $0.sentence.lowercased().contains("grandma") })
        #expect(reminder.due?.lowercased() == "on sunday")
        #expect(reminder.toWhom == nil)
    }

    @Test func recipientIsTheNamedListenerButNeverATitledThirdParty() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let found = PromiseExtractor.extract(from: h.chunks)
        let link = try #require(found.first { $0.sentence.lowercased().contains("text you the link") })
        #expect(link.toWhom == "Priya", "Priya was just addressed; got \(String(describing: link.toWhom))")
        let office = try #require(found.first { $0.sentence.lowercased().contains("call her office") })
        #expect(office.toWhom != "Patel", "Dr. Patel is who is being talked about, not talked to")
    }

    @Test func idsAreStableAndOrderIsChronological() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let a = PromiseExtractor.extract(from: h.chunks)
        let b = PromiseExtractor.extract(from: h.chunks.reversed())
        #expect(a == b, "input order must not matter")
        #expect(Set(a.map(\.id)).count == a.count)
        #expect(a.map(\.wallStart) == a.map(\.wallStart).sorted())
    }

    @Test func titledNamesAreFlagged() {
        let mentions = TextNormalizer.personNames(in: "See Dr. Patel, she is excellent. Thanks Priya.")
        #expect(mentions.first { $0.name.contains("Patel") }?.titled == true)
        #expect(mentions.first { $0.name == "Priya" }?.titled == false)
    }

    @Test func aLoneFirstNameIsFoundEvenWhenTheTaggerMissesIt() {
        // The tagger leaves "Priya" as an ordinary word here; mid-sentence capitalization recovers it.
        #expect(TextNormalizer.personNames(in: "That sounds amazing Priya which hotel did you pick?").map(\.name) == ["Priya"])
    }

    @Test func placesDaysAndSentenceStartsAreNotPeople() {
        #expect(TextNormalizer.personNames(in: "I finally booked the trip Lisbon the second week of March").isEmpty)
        #expect(TextNormalizer.personNames(in: "Right I will send the API specification by Wednesday noon").isEmpty)
        #expect(TextNormalizer.personNames(in: "Thanks everyone same time tomorrow").isEmpty)
    }

    @Test func aCommitmentIsNeverLabelledAsMadeToTheUserThemselves() {
        func chunk(_ id: String, at wall: Double, _ text: String) -> ChunkRecord {
            ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 5, peakDb: -10, meanDb: -30,
                        audioFile: "\(id).m4a", status: .stored, speechConfidence: 0.9, confirmedSeconds: 5, transcript: text)
        }
        // Someone addresses Priya, then says they will do something.
        let day = [chunk("a", at: 40_000, "That sounds amazing Priya which hotel did you pick?"),
                   chunk("b", at: 40_006, "I will text you the link tonight.")]
        #expect(PromiseExtractor.extract(from: day).first?.toWhom == "Priya", "with no profile, the addressed name is the recipient")
        #expect(PromiseExtractor.extract(from: day, userName: "Priya Shah").first?.toWhom == nil, "it is the user, so there is no recipient")
        #expect(PromiseExtractor.extract(from: day, userName: "priya").first?.toWhom == nil, "in any case")
        #expect(PromiseExtractor.extract(from: day, userName: "Jordan").first?.toWhom == "Priya", "a different profile name changes nothing")
    }
}
