import Foundation
import Testing
@testable import Echo

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private struct StubTranscriber: QuestionTranscribing {
    let result: QuestionTranscription
    func transcribe(audio: Data) async -> QuestionTranscription { result }
}

private final class NoMuse: MuseClient {
    var isStub = true
    func complete(_ request: MuseRequest) async throws -> MuseResponse { throw MuseError.offline }
}

@MainActor
struct VoiceAskTests {
    private struct Rig {
        let harness: Harness
        let ask: AskModel
        let history: AskHistoryModel
        let voice: VoiceAskModel
    }

    private func rig(_ heard: QuestionTranscription, clip: String = "q1.wav") async throws -> Rig {
        let h = try await Harness.make()
        let ledger = LedgerModel(store: h.store, defaults: UserDefaults(suiteName: "echo-voice-\(UUID().uuidString)")!)
        let ask = AskModel(store: h.store, ledger: ledger, client: NoMuse(), model: "muse-spark-1.3")
        let history = AskHistoryModel(store: h.store)
        ask.history = history
        let url = repoRoot.appending(path: "Shared/Questions/\(clip)")
        let voice = VoiceAskModel(transcriber: StubTranscriber(result: heard), source: { _ in .clip(url) })
        return Rig(harness: h, ask: ask, history: history, voice: voice)
    }

    @Test func aSpokenQuestionIsUnderstoodThenAskedAndKeptAsAVoiceQuestion() async throws {
        let r = try await rig(.heard("When is the plumber coming?"))
        defer { r.harness.cleanup() }
        let asked = await r.voice.listen(ask: r.ask)
        #expect(asked == "When is the plumber coming?")
        #expect(r.voice.state == .idle)
        let first = try #require(r.history.items.first)
        #expect(first.question == "When is the plumber coming?")
        #expect(first.via == .voice)
        #expect(first.source == .local)
    }

    @Test func aSpokenQuestionsAnswerIsHandedOverForReadingAloudAndAFailedOneIsNot() async throws {
        let ok = try await rig(.heard("When is the plumber coming?"))
        defer { ok.harness.cleanup() }
        var spoken: [String] = []
        ok.voice.afterAnswer = { ask in spoken.append(ask.spokenAnswer ?? "") }
        await ok.voice.listen(ask: ok.ask)
        #expect(spoken.count == 1 && !spoken[0].isEmpty && spoken[0] == ok.ask.spokenAnswer)

        let bad = try await rig(.nothingHeard)
        defer { bad.harness.cleanup() }
        var called = false
        bad.voice.afterAnswer = { _ in called = true }
        await bad.voice.listen(ask: bad.ask)
        #expect(!called)
    }

    @Test func anEmptyRecordingExplainsItselfAndAsksNothing() async throws {
        let r = try await rig(.nothingHeard)
        defer { r.harness.cleanup() }
        let asked = await r.voice.listen(ask: r.ask)
        #expect(asked == nil)
        guard case .problem(let problem) = r.voice.state else { Issue.record("expected a problem, got \(r.voice.state)"); return }
        #expect(problem.message.contains("didn't catch"))
        #expect(!problem.needsSettings)
        #expect(r.history.items.isEmpty)
    }

    @Test func speechRecognitionBeingOffPointsToSettings() async throws {
        let r = try await rig(.speechOff)
        defer { r.harness.cleanup() }
        await r.voice.listen(ask: r.ask)
        guard case .problem(let problem) = r.voice.state else { Issue.record("expected a problem"); return }
        #expect(problem.needsSettings)
    }

    @Test func aRecordingThatCannotBeReadIsAProblemNotACrash() async throws {
        let r = try await rig(.heard("never used"), clip: "missing.wav")
        defer { r.harness.cleanup() }
        let asked = await r.voice.listen(ask: r.ask)
        #expect(asked == nil)
        guard case .problem(let problem) = r.voice.state else { Issue.record("expected a problem"); return }
        #expect(problem.message == QuestionRecordingError.microphoneUnavailable.message)
        #expect(r.history.items.isEmpty)
    }

    @Test func aProblemCanBeDismissedAndTheMicTriedAgain() async throws {
        let r = try await rig(.nothingHeard)
        defer { r.harness.cleanup() }
        await r.voice.listen(ask: r.ask)
        r.voice.dismissProblem()
        #expect(r.voice.state == .idle)
        await r.voice.listen(ask: r.ask)   // tapping the mic straight after a problem starts a new try
        guard case .problem = r.voice.state else { Issue.record("expected the second try to run and fail the same way"); return }
    }

    @Test func cancellingWhileListeningAsksNothing() async throws {
        let r = try await rig(.heard("When is the plumber coming?"))
        defer { r.harness.cleanup() }
        let task = Task { await r.voice.listen(ask: r.ask) }
        for _ in 0..<100 where r.voice.state != .listening { try await Task.sleep(for: .milliseconds(20)) }
        #expect(r.voice.state == .listening)
        r.voice.cancel()
        let asked = await task.value
        #expect(asked == nil)
        #expect(r.voice.state == .idle)
        #expect(r.history.items.isEmpty)
    }
}

struct HistoryGroupingTests {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func date(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func record(_ q: String, _ when: Date) -> AskRecord {
        AskRecord(timestamp: when, question: q, shortAnswer: "a", source: .local, via: .typed, detail: AskDetail(kind: .local, headline: "a"))
    }

    @Test func questionsFallIntoTodayYesterdayAndEarlierNewestFirst() {
        let now = date(10, 15)
        let groups = HistoryGrouping.groups([
            record("old", date(7, 9)), record("today early", date(10, 8)), record("yesterday", date(9, 23)), record("today late", date(10, 14)),
        ], now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "Yesterday", "Earlier"])
        #expect(groups[0].items.map(\.question) == ["today late", "today early"])
        #expect(groups[1].items.map(\.question) == ["yesterday"])
        #expect(groups[2].items.map(\.question) == ["old"])
    }

    @Test func emptyGroupsAreLeftOut() {
        let groups = HistoryGrouping.groups([record("only", date(10, 9))], now: date(10, 15), calendar: calendar)
        #expect(groups.map(\.title) == ["Today"])
        #expect(HistoryGrouping.groups([], now: date(10, 15), calendar: calendar).isEmpty)
    }

    @Test func midnightSplitsTodayFromYesterday() {
        let now = date(10, 0)
        let justBefore = calendar.date(byAdding: .minute, value: -1, to: now)!
        let groups = HistoryGrouping.groups([record("a", now), record("b", justBefore)], now: now, calendar: calendar)
        #expect(groups.map(\.title) == ["Today", "Yesterday"])
    }

    @Test func whenNamesTheDayForRecentQuestions() {
        let now = date(10, 15)
        #expect(HistoryGrouping.when(date(10, 9), now: now, calendar: calendar).hasPrefix("Today "))
        #expect(HistoryGrouping.when(date(9, 9), now: now, calendar: calendar).hasPrefix("Yesterday "))
        #expect(!HistoryGrouping.when(date(3, 9), now: now, calendar: calendar).hasPrefix("Today"))
    }
}
