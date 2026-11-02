import Foundation
import Testing
@testable import Echo

private func promise(_ id: String, chunk: String, kind: Promise.Kind = .commitment, voice: String = "") -> Promise {
    Promise(id: id, chunkID: chunk, kind: kind, timeLabel: "09:05", wallStart: 0, sentence: "I will do \(id).", toWhom: nil, due: nil, context: nil, speakerId: voice)
}

struct PromiseCatcherTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theFirstCommitmentInAFreshMomentIsCaught() {
        var c = PromiseCatcher()
        let all = [promise("a#0", chunk: "a"), promise("a#1", chunk: "a"), promise("b#0", chunk: "b")]
        #expect(c.next(from: all, chunkID: "a", now: t0)?.id == "a#0")
        #expect(c.next(from: all, chunkID: "z", now: t0.addingTimeInterval(60)) == nil, "nothing was said in that moment")
    }

    @Test func notTooSoonAfterTheLastOneAndNotTwice() {
        var c = PromiseCatcher()
        let all = [promise("a#0", chunk: "a"), promise("b#0", chunk: "b"), promise("c#0", chunk: "c")]
        #expect(c.next(from: all, chunkID: "a", now: t0) != nil)
        #expect(c.next(from: all, chunkID: "b", now: t0.addingTimeInterval(5)) == nil, "5 s later is too soon")
        #expect(c.next(from: all, chunkID: "b", now: t0.addingTimeInterval(60)) == nil, "and it isn't offered again once seen")
        #expect(c.next(from: all, chunkID: "c", now: t0.addingTimeInterval(60))?.id == "c#0", "after the gap the next fresh one is")
    }

    @Test func atMostAFewPerSessionAndANewSessionStartsOver() {
        var c = PromiseCatcher()
        let all = (0..<6).map { promise("p\($0)#0", chunk: "m\($0)") }
        var caught = 0
        for i in 0..<6 where c.next(from: all, chunkID: "m\(i)", now: t0.addingTimeInterval(Double(i) * 60)) != nil { caught += 1 }
        #expect(caught == PromiseCatcher.maxPerSession)
        c.newSession()
        #expect(c.next(from: all, chunkID: "m5", now: t0.addingTimeInterval(1_000)) != nil)
    }

    @Test func onlyCommitmentsAreCaughtAndOnlyTheirOwnWhenTheVoiceIsKnown() {
        var c = PromiseCatcher()
        let reminder = [promise("r#0", chunk: "r", kind: .reminder)]
        #expect(c.next(from: reminder, chunkID: "r", now: t0) == nil, "a reminder someone gave isn't a promise the wearer made")
        let mixed = [promise("x#0", chunk: "x", voice: "maya"), promise("x#1", chunk: "x", voice: "me")]
        var mine = PromiseCatcher()
        #expect(mine.next(from: mixed, chunkID: "x", onlyVoice: "me", now: t0)?.id == "x#1")
        var anyone = PromiseCatcher()
        #expect(anyone.next(from: mixed, chunkID: "x", onlyVoice: nil, now: t0)?.id == "x#0")
    }
}

@MainActor
struct PromiseWatcherTests {
    private func rig() throws -> (PromiseWatcher, PipelineModel, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-watch-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = PipelineModel(store: ChunkStore(directory: dir), defaults: UserDefaults(suiteName: "echo-watch-\(UUID().uuidString)")!)
        return (PromiseWatcher(model: model), model, dir)
    }

    private func heard(_ id: String, _ text: String, day: String = DayID.today(), at wall: Double = 100, speaker: String = "") -> ChunkRecord {
        ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                    status: .stored, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day, speakerId: speaker)
    }

    @Test func aPromiseJustHeardIsSurfacedOnceWithItsSentence() throws {
        let (w, model, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        var got: [Promise] = []
        w.onCaught = { got.append($0) }
        let c = heard("a", "I will send the spec by Friday.")
        model.put(c)
        w.chunkStored(c); w.chunkStored(c)
        #expect(got.count == 1 && got[0].sentence.contains("send the spec") && got[0].due == "By Friday")
    }

    @Test func notWhenTurnedOffNorForAnotherDayNorForTalkWithNoPromise() throws {
        let (w, model, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        var got = 0
        w.onCaught = { _ in got += 1 }
        let last = heard("old", "I will call you next week.", day: "2000-01-01"), idle = heard("idle", "The weather is lovely.", at: 200)
        model.put(last); model.put(idle)
        w.chunkStored(last); w.chunkStored(idle)
        w.isEnabled = { false }
        let promise = heard("p", "I will pay the rent.", at: 300)
        model.put(promise)
        w.chunkStored(promise)
        #expect(got == 0)
    }

    @Test func onceTheWearersVoiceIsKnownOnlyTheirPromisesCount() throws {
        let (w, model, dir) = try rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        var got: [String] = []
        w.onCaught = { got.append($0.chunkID) }
        w.myVoice = { "me" }
        let hers = heard("hers", "I will review the design document.", speaker: "maya")
        model.put(hers); w.chunkStored(hers)
        #expect(got.isEmpty)
        let mine = heard("mine", "I will send the API specification.", at: 200, speaker: "me")
        model.put(mine); w.chunkStored(mine)
        #expect(got == ["mine"])
    }
}

@MainActor
struct KeepPromiseTests {
    @Test func theWatchCanAskForAReminderAndIsToldWhetherItWorked() async throws {
        final class Seen { var ids: [String] = [] }
        let seen = Seen()
        struct Stub: QuestionTranscribing { func transcribe(audio: Data) async -> QuestionTranscription { .nothingHeard } }
        let r = WatchRequests(transcriber: Stub(), answer: { _, _ in WatchAnswer(text: "", source: .none) }, history: { [] },
                              keepPromise: { seen.ids.append($0); return $0 == "good#0" })
        let ok = try #require(await r.handle([Wire.typeKey: Wire.keepPromise, Wire.idKey: "good#0"]))
        let bad = try #require(await r.handle([Wire.typeKey: Wire.keepPromise, Wire.idKey: "gone#0"]))
        let none = try #require(await r.handle([Wire.typeKey: Wire.keepPromise]))
        #expect(ok[Wire.okKey] as? Bool == true && bad[Wire.okKey] as? Bool == false && none[Wire.okKey] as? Bool == false)
        #expect(seen.ids == ["good#0", "gone#0"], "a request with no promise isn't passed on")
    }

    @Test func catchingPromisesIsOnUntilTurnedOffAndRemembered() {
        let d = UserDefaults(suiteName: "echo-catch-\(UUID().uuidString)")!
        let p = ProfileStore(defaults: d, arguments: [])
        #expect(p.catchPromises)
        p.catchPromises = false
        #expect(!ProfileStore(defaults: d, arguments: []).catchPromises)
    }
}
