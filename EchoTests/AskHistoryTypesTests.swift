import Foundation
import Testing
@testable import Echo

struct AskHistoryTypesTests {
    @Test func aHistoryItemSurvivesTheWireFormat() throws {
        let item = HistoryItem(id: "abc", timestamp: Date(timeIntervalSince1970: 1_793_500_000), question: "When is the plumber coming?",
                               answer: "Friday at 10.", source: .local, via: .watchVoice)
        let back = try #require(HistoryItem(dictionary: item.dictionary))
        #expect(back == item)
    }

    @Test func aMalformedItemIsRejectedAndUnknownValuesAreNotTrusted() {
        #expect(HistoryItem(dictionary: [:]) == nil)
        #expect(HistoryItem(dictionary: ["id": "x", "ts": 1.0, "q": "", "a": "ok"]) == nil, "an empty question is not a history entry")
        #expect(HistoryItem(dictionary: ["id": "x", "ts": "yesterday", "q": "q", "a": "a"]) == nil)
        let odd = HistoryItem(dictionary: ["id": "x", "ts": 1.0, "q": "q", "a": "a", "src": "martian", "via": "telepathy"])
        #expect(odd?.source == WatchAnswer.Source.none && odd?.via == AskVia.typed, "unknown source and via fall back to the safe values")
    }

    @Test func itemsAreCodableForTheWatchCache() throws {
        let items = [HistoryItem(question: "a?", answer: "x", source: .muse, via: .voice), HistoryItem(question: "b?", answer: "y", source: .local, via: .typed)]
        let data = try JSONEncoder().encode(items)
        #expect(try JSONDecoder().decode([HistoryItem].self, from: data) == items)
    }

    @Test func everyWayOfAskingHasALabelAndOnlyVoiceCountsAsVoice() {
        #expect(AskVia.allCases.allSatisfy { !$0.label.isEmpty })
        #expect(AskVia.allCases.filter(\.isVoice) == [.voice, .watchVoice])
    }

    @Test func ageLabelsAreShort() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func age(_ seconds: Double) -> String { AgeLabel.short(from: now.addingTimeInterval(-seconds), to: now) }
        #expect(age(5) == "now" && age(59) == "now")
        #expect(age(60) == "1m" && age(59 * 60) == "59m")
        #expect(age(3_600) == "1h" && age(23 * 3_600) == "23h")
        #expect(age(86_400) == "1d" && age(3 * 86_400) == "3d")
        #expect(AgeLabel.short(from: now.addingTimeInterval(500), to: now) == "now", "a time in the future is just 'now'")
    }

    @Test func aWatchAnswerCarriesWhatWasHeard() throws {
        let answer = WatchAnswer(text: "Friday at 10.", source: .local, milliseconds: 40, heard: "When is the plumber coming?")
        let back = try #require(WatchAnswer(dictionary: answer.dictionary))
        #expect(back == answer && back.heard == "When is the plumber coming?")
        let plain = try #require(WatchAnswer(dictionary: WatchAnswer(text: "x", source: .muse).dictionary))
        #expect(plain.heard == nil, "a typed question has nothing 'heard'")
    }

    @Test func speechTextReadsWellAloud() {
        #expect(SpeechText.prepare("  You promised **two** things.\n\nSend the spec  by_Wednesday.  ") == "You promised two things. Send the spec by Wednesday.")
        #expect(SpeechText.prepare("") == "" && SpeechText.prepare("   \n ") == "")
        let long = String(repeating: "This is a fairly ordinary sentence about the day. ", count: 30)
        let spoken = SpeechText.prepare(long)
        #expect(spoken.count <= SpeechText.limit && spoken.hasSuffix("."), "cut at a sentence, not mid-word")
    }

    @Test func theNewWireKeysAreDistinct() {
        let keys = [Wire.transcribe, Wire.history, Wire.demoVoiceAsk, Wire.audioKey, Wire.heardKey, Wire.reasonKey, Wire.viaKey, Wire.itemsKey,
                    Wire.ask, Wire.demoQuickAsk, Wire.demoStart, Wire.session]
        #expect(Set(keys).count == keys.count)
    }
}
