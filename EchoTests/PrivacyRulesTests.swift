import Foundation
import Testing
@testable import Echo

private func moment(_ id: String, day: String = "2026-11-02", at wall: Double, dur: Double = 60, status: ChunkStatus = .stored) -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: dur, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: status, speechConfidence: 1, confirmedSeconds: dur, transcript: "t \(id)", dayId: day)
}

struct ForgetWindowTests {
    @Test func theLastMinutesAreCountedBackFromTheNewestMoment() {
        // a day of moments every ten minutes, each a minute long
        let day = (0..<12).map { moment("m\($0)", at: Double($0) * 600) }
        #expect(ForgetWindow.chunks(in: day, minutes: 10).map(\.id) == ["m11"], "10 minutes before the end of the newest (a minute long) catches only it")
        #expect(ForgetWindow.chunks(in: day, minutes: 30).map(\.id) == ["m9", "m10", "m11"])
        #expect(ForgetWindow.chunks(in: day, minutes: 60).count == 6 || ForgetWindow.chunks(in: day, minutes: 60).count == 7)
        #expect(ForgetWindow.chunks(in: day, minutes: 24 * 60).count == 12, "a long window reaches the whole day")
    }

    @Test func aMomentThatOverlapsTheWindowCounts() {
        let day = [moment("old", at: 0, dur: 30), moment("straddles", at: 940, dur: 120), moment("new", at: 1_100, dur: 30)]
        #expect(ForgetWindow.chunks(in: day, minutes: 5).map(\.id) == ["straddles", "new"], "begins before the cutoff, ends after it")
    }

    @Test func onlyTheNewestDayIsTouchedAndEveryStatusCounts() {
        let all = [moment("last-week", day: "2026-10-26", at: 36_000), moment("today-a", at: 36_000, status: .dropped),
                   moment("today-b", at: 36_030, status: .vad), moment("today-c", at: 36_060, status: .received)]
        let gone = ForgetWindow.chunks(in: all, minutes: 10).map(\.id)
        #expect(Set(gone) == ["today-a", "today-b", "today-c"], "last week stays; half-processed moments go too")
    }

    @Test func nothingOrNonsenseForgetsNothing() {
        #expect(ForgetWindow.chunks(in: [], minutes: 10).isEmpty)
        #expect(ForgetWindow.chunks(in: [moment("a", at: 0)], minutes: 0).isEmpty && ForgetWindow.chunks(in: [moment("a", at: 0)], minutes: -5).isEmpty)
        #expect(ForgetWindow.options == [5, 10, 30, 60] && ForgetWindow.title(minutes: 60) == "hour" && ForgetWindow.title(minutes: 10) == "10 minutes")
    }
}

struct PrivacyGateTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theCommandsAreRecognisedHoweverTheRecognizerWritesThem() {
        for s in ["This is off the record.", "off-the-record please", "Okay, so, OFF THE RECORD, between us", "that was Off The Record!"] {
            #expect(PrivacyGate.isOffCommand(s), "\(s)")
        }
        for s in ["Back on the record.", "we're back on the record now", "ok on the record again", "back-on-the-record"] {
            #expect(PrivacyGate.isBackOnCommand(s), "\(s)")
        }
        for s in ["I will send the record to Priya", "the record shows four percent", "off the cuff", "Hello there"] {
            #expect(!PrivacyGate.isOffCommand(s) && !PrivacyGate.isBackOnCommand(s), "\(s)")
        }
    }

    @Test func offThenPrivateThenBackOn() {
        var gate = PrivacyGate()
        #expect(!gate.isPrivate(now: t0))
        #expect(gate.decide(transcript: "What time is it", now: t0) == .keep)
        #expect(gate.decide(transcript: "This is off the record", now: t0) == .dropCommand, "the command isn't kept either")
        #expect(gate.isPrivate(now: t0.addingTimeInterval(60)))
        #expect(gate.decide(transcript: "My password is hunter2", now: t0.addingTimeInterval(60)) == .dropPrivate)
        #expect(gate.decide(transcript: "something else private", now: t0.addingTimeInterval(120)) == .dropPrivate)
        #expect(gate.decide(transcript: "Okay, back on the record", now: t0.addingTimeInterval(180)) == .dropCommand)
        #expect(!gate.isPrivate(now: t0.addingTimeInterval(181)))
        #expect(gate.decide(transcript: "The plumber comes on Friday", now: t0.addingTimeInterval(200)) == .keep)
    }

    @Test func ItEndsByItselfAfterTenMinutesAndASecondOffExtendsIt() {
        var gate = PrivacyGate()
        _ = gate.decide(transcript: "off the record", now: t0)
        #expect(gate.decide(transcript: "still private", now: t0.addingTimeInterval(9 * 60)) == .dropPrivate)
        #expect(gate.decide(transcript: "back to normal", now: t0.addingTimeInterval(10 * 60 + 1)) == .keep, "ten minutes passed")
        _ = gate.decide(transcript: "off the record", now: t0.addingTimeInterval(20 * 60))
        _ = gate.decide(transcript: "off the record again", now: t0.addingTimeInterval(25 * 60))
        #expect(gate.isPrivate(now: t0.addingTimeInterval(34 * 60)), "saying it again starts the ten minutes over")
    }

    @Test func aMomentWithNoTranscriptIsJudgedOnlyByTheState() {
        var gate = PrivacyGate()
        #expect(gate.decide(transcript: nil, now: t0) == .keep)
        _ = gate.decide(transcript: "off the record", now: t0)
        #expect(gate.decide(transcript: nil, now: t0.addingTimeInterval(5)) == .dropPrivate)
        gate.end()
        #expect(!gate.isPrivate(now: t0.addingTimeInterval(6)))
    }
}

@MainActor
struct RecordingPrivacyTests {
    @Test func theAnnounceChoiceIsRememberedAndOnlyReportedWhenItChanges() {
        let d = UserDefaults(suiteName: "echo-priv-\(UUID().uuidString)")!
        var told: [Bool] = []
        let p = RecordingPrivacy(defaults: d)
        p.onAnnounceChanged = { told.append($0) }
        #expect(!p.announce)
        p.announce = true; p.announce = true; p.announce = false
        #expect(told == [true, false])
        p.announce = true
        #expect(RecordingPrivacy(defaults: d).announce, "it is still on after a relaunch")
    }

    @Test func goingOffTheRecordIsVisibleAndTheButtonEndsIt() {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let p = RecordingPrivacy(defaults: UserDefaults(suiteName: "echo-priv2-\(UUID().uuidString)")!, now: { now })
        #expect(!p.isOffTheRecord && p.decide(transcript: "hello") == .keep)
        #expect(p.decide(transcript: "this is off the record") == .dropCommand && p.isOffTheRecord)
        p.resume()
        #expect(!p.isOffTheRecord && p.decide(transcript: "plumber on friday") == .keep)
    }
}

@MainActor
struct ForgetRecentTests {
    private func model() throws -> (PipelineModel, ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-forget-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        let m = PipelineModel(store: store, defaults: UserDefaults(suiteName: "echo-forget-\(UUID().uuidString)")!)
        m.now = { Date(timeIntervalSince1970: 1_793_000_000) }
        return (m, store, dir)
    }

    @Test func theLastMinutesGoWithTheirAudioTheAnswersThatUsedThemAndTheSummary() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        let today = DayID.today(now: m.now())
        let old = moment("old", day: today, at: 1_000), recent = moment("recent", day: today, at: 5_000)
        for c in [old, recent] {
            await store.upsert(c)
            try await store.write(audio: Data([1, 2, 3]), named: c.audioFile)
            m.put(c)
        }
        await store.saveDigest(json: "{}", model: "m", isStub: false, day: today)
        await store.upsertHistory(AskRecord(question: "uses recent", shortAnswer: "a", source: .local, via: .typed,
                                            detail: AskDetail(kind: .local, headline: "a", sourceChunkIDs: ["recent"])))
        await store.upsertHistory(AskRecord(question: "uses old", shortAnswer: "a", source: .local, via: .typed,
                                            detail: AskDetail(kind: .local, headline: "a", sourceChunkIDs: ["old"])))
        let gone = await m.forgetLast(minutes: 10)
        #expect(gone == ["recent"] && m.chunks.map(\.id) == ["old"])
        let left = await store.all().map(\.id)
        let history = await store.history().map(\.question)
        let digest = await store.loadDigest(day: today)
        #expect(left == ["old"] && history == ["uses old"] && digest == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "chunks/recent.m4a").path), "the audio file is gone")
        #expect(FileManager.default.fileExists(atPath: dir.appending(path: "chunks/old.m4a").path))
        let none = await m.forgetLast(minutes: 0)
        #expect(none.isEmpty)
    }

    @Test func remindersAboutForgottenMomentsAreCancelled() async {
        let defaults = UserDefaults(suiteName: "echo-forget2-\(UUID().uuidString)")!
        final class Fake: NotificationScheduling {
            var removed: [String] = []
            func ensureAuthorized() async -> Bool { true }
            func add(id: String, title: String, body: String, at date: Date) async throws {}
            func remove(ids: [String]) { removed += ids }
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let r = Reminders(scheduler: Fake(), defaults: defaults, now: { now })
        func promise(_ id: String) -> Promise {
            Promise(id: id, chunkID: String(id.split(separator: "#")[0]), kind: .commitment, timeLabel: "09:00", wallStart: 0, sentence: "I will x.", toWhom: nil, due: nil, context: nil)
        }
        await r.schedule(promise("keepme#0"), at: now.addingTimeInterval(600))
        await r.schedule(promise("gone#0"), at: now.addingTimeInterval(600))
        await r.schedule(promise("gone#1"), at: now.addingTimeInterval(900))
        r.cancel(forChunkIDs: ["gone"])
        #expect(r.scheduled.keys.sorted() == ["keepme#0"])
    }

    @Test func theWatchCanAskForItAndTheMinutesAreKeptSensible() async throws {
        final class Seen { var minutes: [Int] = [] }
        let seen = Seen()
        struct Stub: QuestionTranscribing { func transcribe(audio: Data) async -> QuestionTranscription { .nothingHeard } }
        let requests = WatchRequests(transcriber: Stub(), answer: { _, _ in WatchAnswer(text: "", source: .none) }, history: { [] },
                                     forgetRecent: { seen.minutes.append($0); return 3 })
        let reply = try #require(await requests.handle([Wire.typeKey: Wire.forget, Wire.minutesKey: 10]))
        #expect(reply[Wire.okKey] as? Bool == true && reply[Wire.countKey] as? Int == 3)
        _ = await requests.handle([Wire.typeKey: Wire.forget, Wire.minutesKey: 9_999])
        _ = await requests.handle([Wire.typeKey: Wire.forget, Wire.minutesKey: -4])
        _ = await requests.handle([Wire.typeKey: Wire.forget])
        #expect(seen.minutes == [10, 120, 1, 10], "kept between a minute and two hours, ten by default")
    }
}
