import Foundation
import Testing
@testable import Echo

private struct StubTranscriber: QuestionTranscribing {
    var result: QuestionTranscription
    func transcribe(audio: Data) async -> QuestionTranscription { result }
}

/// Remembers what the watch asked.
@MainActor
private final class Asked {
    var calls: [(String, AskVia)] = []
}

@MainActor
struct WatchRequestsTests {
    private func requests(_ result: QuestionTranscription = .heard("What did I promise people today?"), asked: Asked? = nil,
                          history: [HistoryItem] = []) -> WatchRequests {
        let asked = asked ?? Asked()
        return WatchRequests(transcriber: StubTranscriber(result: result),
                      answer: { q, via in asked.calls.append((q, via)); return WatchAnswer(text: "An answer.", source: .muse, milliseconds: 5) },
                      history: { history })
    }

    private let audio = Data(repeating: 7, count: 2_000)

    // MARK: Understanding a recorded question

    @Test func aRecordedQuestionComesBackAsText() async throws {
        let reply = try #require(await requests().handle([Wire.typeKey: Wire.transcribe, Wire.audioKey: audio]))
        #expect(reply[Wire.okKey] as? Bool == true && reply[Wire.heardKey] as? String == "What did I promise people today?")
        #expect(VoiceReply(dictionary: reply) == .heard("What did I promise people today?"))
    }

    @Test func eachFailureReplyCarriesAReasonTheWatchCanExplain() async throws {
        for (result, reason) in [(QuestionTranscription.nothingHeard, "nothing-heard"), (.speechOff, "speech-off"), (.unavailable, "unavailable"), (.timedOut, "timed-out")] {
            let reply = try #require(await requests(result).handle([Wire.typeKey: Wire.transcribe, Wire.audioKey: audio]))
            #expect(reply[Wire.okKey] as? Bool == false && reply[Wire.reasonKey] as? String == reason)
            let parsed = VoiceReply(dictionary: reply)
            #expect(parsed == .failed(reason: reason) && parsed.message != nil)
        }
    }

    @Test func missingOrEmptyAudioIsNotUnderstood() async throws {
        for message in [[Wire.typeKey: Wire.transcribe], [Wire.typeKey: Wire.transcribe, Wire.audioKey: Data()], [Wire.typeKey: Wire.transcribe, Wire.audioKey: "text"]] as [[String: Any]] {
            let reply = try #require(await requests().handle(message))
            #expect(reply[Wire.okKey] as? Bool == false && reply[Wire.reasonKey] as? String == "nothing-heard")
        }
    }

    @Test func aPhoneThatCannotBeReachedIsExplained() {
        #expect(VoiceReply(dictionary: nil) == .unreachable)
        #expect(VoiceReply.unreachable.message?.contains("not reachable") == true)
        #expect(VoiceReply.heard("x").message == nil)
        #expect(VoiceReply(dictionary: [Wire.okKey: true, Wire.heardKey: ""]) != .heard(""), "an empty transcript is not a question")
        #expect(VoiceReply(dictionary: ["junk": 1]).message != nil)
    }

    // MARK: Asking

    @Test func aQuestionIsAnsweredAndRemembersHowItWasAsked() async throws {
        let asked = Asked()
        let r = requests(asked: asked)
        let typed = try #require(await r.handle([Wire.typeKey: Wire.ask, Wire.questionKey: "  When is the plumber coming? "]))
        #expect(WatchAnswer(dictionary: typed)?.text == "An answer.")
        _ = await r.handle([Wire.typeKey: Wire.ask, Wire.questionKey: "By voice", Wire.viaKey: AskVia.watchVoice.rawValue])
        _ = await r.handle([Wire.typeKey: Wire.ask, Wire.questionKey: "Odd", Wire.viaKey: "telepathy"])
        #expect(asked.calls.map(\.0) == ["When is the plumber coming?", "By voice", "Odd"], "tidied")
        #expect(asked.calls.map(\.1) == [.watch, .watchVoice, .watch], "unknown ways of asking are treated as the plain watch")
    }

    @Test func aBlankQuestionIsRefusedWithoutAsking() async throws {
        let asked = Asked()
        let reply = try #require(await requests(asked: asked).handle([Wire.typeKey: Wire.ask, Wire.questionKey: "   "]))
        #expect(reply[Wire.okKey] as? Bool == false && asked.calls.isEmpty)
        let none = try #require(await requests(asked: asked).handle([Wire.typeKey: Wire.ask]))
        #expect(none[Wire.okKey] as? Bool == false && asked.calls.isEmpty)
    }

    // MARK: History

    @Test func theHistoryReplyHoldsAtMostEightItemsThatSurviveTheWire() async throws {
        let items = (0..<12).map { HistoryItem(question: "q\($0)?", answer: "a\($0)", source: .local, via: .typed) }
        let reply = try #require(await requests(history: items).handle([Wire.typeKey: Wire.history]))
        let raw = try #require(reply[Wire.itemsKey] as? [[String: Any]])
        #expect(raw.count == HistoryCache.limit)
        let back = raw.compactMap { HistoryItem(dictionary: $0) }
        #expect(back.map(\.id) == items.prefix(8).map(\.id) && back.map(\.question) == items.prefix(8).map(\.question))
        #expect(zip(back, items).allSatisfy { abs($0.timestamp.timeIntervalSince($1.timestamp)) < 0.001 }, "times survive to the millisecond")
        let size = try JSONSerialization.data(withJSONObject: reply.merging([:]) { a, _ in a }.mapValues { $0 is Bool ? 1 : $0 }).count
        #expect(size < 8_000, "a full history is a few KB, far under any message limit (\(size) bytes)")
    }

    @Test func noHistoryIsAnEmptyListNotAnError() async throws {
        let reply = try #require(await requests().handle([Wire.typeKey: Wire.history]))
        #expect(reply[Wire.okKey] as? Bool == true && (reply[Wire.itemsKey] as? [[String: Any]])?.isEmpty == true)
    }

    @Test func anUnknownMessageIsLeftForSomeoneElse() async {
        #expect(await requests().handle([Wire.typeKey: "something.else"]) == nil)
        #expect(await requests().handle([:]) == nil)
    }
}

struct HistoryCacheTests {
    private func cache() -> HistoryCache { HistoryCache(defaults: UserDefaults(suiteName: "echo-cache-\(UUID().uuidString)")!) }
    private func item(_ q: String, at t: Double = 0) -> HistoryItem {
        HistoryItem(timestamp: Date(timeIntervalSince1970: 1_700_000_000 + t), question: q, answer: "a", source: .local, via: .typed)
    }

    @Test func whatThePhoneSendsReplacesTheListNewestFirstAndCapped() {
        let c = cache()
        c.replace(with: (0..<12).map { item("q\($0)", at: Double($0)) })
        #expect(c.items.count == 8 && c.items.first?.question == "q11" && c.items.last?.question == "q4")
        c.replace(with: [item("only one")])
        #expect(c.items.map(\.question) == ["only one"], "the phone's list wins")
    }

    @Test func anEmptyListFromThePhoneClearsTheWatchAfterForgetMyDay() {
        let c = cache()
        c.replace(with: [item("a"), item("b")])
        c.replace(with: [])
        #expect(c.items.isEmpty)
    }

    @Test func aFreshAnswerShowsAtOnceAndARepeatedQuestionDoesNotAppearTwice() {
        let c = cache()
        c.replace(with: [item("first", at: 0), item("second", at: 1)])
        c.insert(item("Third", at: 2))
        c.insert(HistoryItem(timestamp: Date(timeIntervalSince1970: 1_700_000_100), question: "FIRST", answer: "newer", source: .muse, via: .watchVoice))
        #expect(c.items.map(\.question) == ["FIRST", "Third", "second"], "same question, any case, moves to the top")
        #expect(c.items.first?.answer == "newer")
    }

    @Test func theCacheSurvivesBeingReopenedAndCanBeCleared() {
        let defaults = UserDefaults(suiteName: "echo-cache-\(UUID().uuidString)")!
        HistoryCache(defaults: defaults).replace(with: [item("kept")])
        #expect(HistoryCache(defaults: defaults).items.map(\.question) == ["kept"])
        HistoryCache(defaults: defaults).clear()
        #expect(HistoryCache(defaults: defaults).items.isEmpty)
    }

    @Test func insertingNeverExceedsTheLimit() {
        let c = cache()
        for i in 0..<20 { c.insert(item("q\(i)", at: Double(i))) }
        #expect(c.items.count == HistoryCache.limit && c.items.first?.question == "q19")
    }
}
