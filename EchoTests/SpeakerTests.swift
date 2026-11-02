import Foundation
import Testing
@testable import Echo

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private func print26(_ base: Float, wobble: Float = 0) -> VoicePrint {
    VoicePrint(values: (0..<VoicePrint.dimensions).map { Float($0) * 0.01 + base * VoicePrint.scale[$0] + wobble * VoicePrint.scale[$0] })
}

private func chunk(_ id: String, speaker: String, _ text: String, at t: Double = 0) -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: t, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: .stored, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: DayID.today(), speakerId: speaker)
}

struct SpeakerBookTests {
    @Test func aNewVoiceStartsAVoiceAndAClosePrintJoinsIt() {
        var book = SpeakerBook()
        let first = book.assign(print26(0))
        let again = book.assign(print26(0, wobble: 0.3))
        let other = book.assign(print26(6))
        #expect(first.id == again.id && first.label == "Voice 1" && other.label == "Voice 2" && other.id != first.id)
        #expect(book.speakers.count == 2 && book.speakers.first { $0.id == first.id }?.count == 2)
    }

    @Test func aVoiceDriftsTowardWhatItHearsButStaysTheSameVoice() {
        var book = SpeakerBook()
        let id = book.assign(print26(0)).id
        for i in 1...6 { book.assign(print26(Float(i) * 0.2)) }
        #expect(book.speakers.count == 1 && book.speakers[0].id == id && book.speakers[0].count == 7)
        let centroid = book.speakers[0].centroid.values[3]
        #expect(centroid > print26(0).values[3], "its centre moved toward the newer prints")
    }

    @Test func mergingFoldsOneVoiceIntoAnotherKeepingTheNameAndMe() {
        var book = SpeakerBook()
        let a = book.assign(print26(0)).id, b = book.assign(print26(6)).id
        book.speakers[book.speakers.firstIndex { $0.id == b }!].name = "Maya"
        book.setMe(b)
        book.merge(b, into: a)
        #expect(book.speakers.count == 1 && book.speakers[0].id == a)
        #expect(book.speakers[0].name == "Maya" && book.speakers[0].isMe && book.speakers[0].count == 2)
        book.merge("nobody", into: a)
        #expect(book.speakers.count == 1, "an unknown voice changes nothing")
    }

    @Test func thereIsOnlyOneMeAndVoicesThatSoundAlikeAreOfferedForMerging() {
        var book = SpeakerBook()
        let a = book.assign(print26(0)).id, b = book.assign(print26(3)).id
        book.setMe(a); book.setMe(b)
        #expect(book.me?.id == b && book.speakers.filter(\.isMe).count == 1)
        book.setMe(nil)
        #expect(book.me == nil)
        var close = SpeakerBook()
        close.speakers = [Voice(id: "x", label: "Voice 1", name: nil, isMe: false, centroid: print26(0), count: 3, colorIndex: 0, created: Date()),
                          Voice(id: "y", label: "Voice 2", name: nil, isMe: false, centroid: print26(1.0), count: 3, colorIndex: 1, created: Date()),
                          Voice(id: "z", label: "Voice 3", name: nil, isMe: false, centroid: print26(9), count: 3, colorIndex: 2, created: Date())]
        #expect(close.mergeCandidates().map { [$0.a, $0.b] } == [["x", "y"]])
    }

    @Test func theNameOnScreenIsTheNameOrTheLabel() {
        var v = Voice(id: "x", label: "Voice 3", name: nil, isMe: false, centroid: print26(0), count: 1, colorIndex: 0, created: Date())
        #expect(v.display == "Voice 3" && v.initial == "3", "a number until it has a name")
        v.name = "maya"
        #expect(v.display == "maya" && v.initial == "M")
        v.name = ""
        #expect(v.display == "Voice 3")
    }
}

struct VoicePrintTests {
    private func lines(_ stem: String) throws -> [(speaker: String, samples: [Int16])] {
        let wav = try WAV.read(repoRoot.appending(path: "Echo Watch App/Resources/\(stem).wav"))
        let manifest = try DemoManifest.load(from: repoRoot.appending(path: "Echo Watch App/Resources/\(stem).json"))
        return manifest.scenes.flatMap(\.lines).map { line in
            (line.speaker, Array(wav.samples[Int(line.start * 16_000)..<min(wav.samples.count, Int(line.end * 16_000))]))
        }
    }

    @Test func prints_roundTripThroughStorageAndSilenceHasNone() throws {
        let day = try lines("demo_day")
        let p = try #require(VoicePrint.make(from: day[0].samples))
        #expect(p.values.count == VoicePrint.dimensions && VoicePrint(data: p.data) == p)
        #expect(VoicePrint(data: Data(count: 5)) == nil)
        #expect(VoicePrint.make(from: [Int16](repeating: 0, count: 16_000)) == nil, "nothing was said")
        #expect(VoicePrint.make(from: Array(day[0].samples.prefix(1_000))) == nil, "too short to tell")
    }

    /// What the phone receives: the line after the watch's compression, read back from a file.
    private func compressed(_ samples: [Int16]) throws -> [Int16] {
        let audio = try #require(AudioCodec.encodeAAC(samples: samples, sampleRate: 16_000, bitRate: 20_000))
        let url = FileManager.default.temporaryDirectory.appending(path: "voice-\(UUID().uuidString).m4a")
        try audio.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try #require(AudioDecoder.pcm16k(url: url))
    }

    @Test func compressedAudioReadsBackAtTheRightRateAndLength() throws {
        let line = try lines("demo_day")[1].samples
        let back = try compressed(line)
        #expect(abs(back.count - line.count) < 2_400, "about the same length (\(back.count) vs \(line.count))")
        #expect(VoicePrint.make(from: back) != nil)
    }

    /// The ground-truth check: every demo line has a known speaker. Told apart in the order the app hears them (last week,
    /// then today) and after the same compression, the voices should come out as the people.
    @Test func theDemoRecordingsComeOutAsTheirEightSpeakers() throws {
        let all = try lines("demo_day_prev") + lines("demo_day")
        var book = SpeakerBook()
        var assigned: [(speaker: String, voice: String)] = []
        for line in all {
            let p = try #require(VoicePrint.make(from: try compressed(line.samples)), "\(line.speaker) has enough speech")
            assigned.append((line.speaker, book.assign(p).id))
        }
        let people = Set(all.map(\.speaker))
        var correct = 0
        for voice in Set(assigned.map(\.voice)) {
            let said = assigned.filter { $0.voice == voice }.map(\.speaker)
            correct += Dictionary(grouping: said, by: { $0 }).values.map(\.count).max() ?? 0
        }
        let purity = Double(correct) / Double(all.count)
        #expect(purity >= 0.9, "\(Int(purity * 100))% of lines are under the right voice")
        #expect((people.count - 1)...(people.count + 3) ~= book.speakers.count, "\(book.speakers.count) voices for \(people.count) people")
        // the person who talks most (the wearer) has one clear voice
        let levin = assigned.filter { $0.speaker == "Levin" }
        let top = Dictionary(grouping: levin, by: \.voice).values.map(\.count).max() ?? 0
        #expect(Double(top) / Double(levin.count) >= 0.85, "Levin's own lines are mostly one voice")
    }
}

struct SpeakerStoreTests {
    private func store() throws -> (ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-voices-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ChunkStore(directory: dir), dir)
    }

    @Test func voicesAndWhoSaidWhatSurviveAReopen() async throws {
        let (s, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var book = SpeakerBook()
        let v = book.assign(print26(0))
        await s.saveSpeaker(v)
        await s.upsert(chunk("c1", speaker: "", "hello"))
        await s.setVoice(chunkID: "c1", speakerID: v.id, print: print26(0).data)
        let reopened = ChunkStore(directory: dir)
        let voices = await reopened.speakers()
        let said = await reopened.all().first?.speakerId
        #expect(voices.count == 1 && voices[0].id == v.id && voices[0].label == "Voice 1" && voices[0].count == 1)
        #expect(said == v.id)
        // rewriting the moment (its status changes as it is processed) must not forget whose voice it is
        var c = try #require(await reopened.all().first)
        c.transcript = "hello again"
        await reopened.upsert(c)
        let still = await reopened.all().first?.speakerId
        #expect(still == v.id)
    }

    @Test func forgettingAVoiceUnattributesItsMomentsAndResetClearsEveryVoice() async throws {
        let (s, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        var book = SpeakerBook()
        let a = book.assign(print26(0)), b = book.assign(print26(6))
        await s.saveSpeaker(a); await s.saveSpeaker(b)
        await s.upsert(chunk("c1", speaker: a.id, "one"))
        await s.upsert(chunk("c2", speaker: b.id, "two", at: 1))
        await s.deleteSpeaker(id: a.id)
        let after = await s.all().map(\.speakerId)
        let left = await s.speakers().map(\.id)
        #expect(after == ["", b.id] && left == [b.id])
        await s.reset()
        let none = await s.speakers()
        #expect(none.isEmpty)
    }
}

@MainActor
struct VoiceBookModelTests {
    private func model() throws -> (VoiceBookModel, ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-vbm-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        return (VoiceBookModel(store: store), store, dir)
    }

    @Test func identifyingSavesTheVoiceAndTheMomentsAttribution() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(chunk("c1", speaker: "", "one"))
        let id = try #require(await m.identify(chunkID: "c1", print: print26(0)))
        let nothing = await m.identify(chunkID: "c1", print: nil)
        #expect(nothing == nil, "too little speech to tell")
        let stored = await store.all().first?.speakerId
        let saved = await store.speakers().count
        #expect(stored == id && saved == 1 && m.voice(id: id)?.label == "Voice 1")
        let reloaded = VoiceBookModel(store: store)
        await reloaded.load()
        #expect(reloaded.voices.map(\.id) == [id])
    }

    @Test func namingMeMergingAndForgettingAllStick() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        for (i, base) in [Float(0), 6, 12].enumerated() {
            await store.upsert(chunk("c\(i)", speaker: "", "t\(i)", at: Double(i)))
            _ = await m.identify(chunkID: "c\(i)", print: print26(base))
        }
        let ids = m.voices.map(\.id)
        #expect(ids.count == 3)
        await m.rename(ids[0], to: "  Maya ")
        await m.setMe(ids[1])
        #expect(m.voice(id: ids[0])?.name == "Maya" && m.me?.id == ids[1])
        await m.setMe(ids[2])
        #expect(m.voices.filter(\.isMe).count == 1 && m.me?.id == ids[2])
        await m.merge(ids[2], into: ids[0])
        let moved = await store.all().map(\.speakerId)
        #expect(m.voices.count == 2 && moved.filter { $0 == ids[0] }.count == 2, "the merged voice's moments follow it")
        #expect(m.voice(id: ids[0])?.isMe == true && m.voice(id: ids[0])?.name == "Maya")
        await m.forget(ids[1])
        let afterForget = await store.all().map(\.speakerId)
        #expect(m.voices.count == 1 && afterForget.contains(""))
        m.clear()
        #expect(m.voices.isEmpty)
    }

    @Test func theVoiceHeardMostIsOfferedAsMeOnlyOnceThereIsEnoughToGoOn() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        func hear(_ i: Int, _ base: Float) async {
            await store.upsert(chunk("h\(i)", speaker: "", "x", at: Double(i)))
            _ = await m.identify(chunkID: "h\(i)", print: print26(base))
        }
        for i in 0..<3 { await hear(i, 0) }
        #expect(m.suggestedMe == nil, "too little heard to guess")
        for i in 3..<6 { await hear(i, 0) }
        await hear(9, 8)
        #expect(m.suggestedMe?.label == "Voice 1")
        await m.setMe(m.suggestedMe?.id)
        #expect(m.suggestedMe == nil, "once the person has said, no more guessing")
    }
}

@MainActor
struct OwnCommitmentsTests {
    private func plan(_ q: String, me: String?) -> TierTwoPlan {
        let chunks = [chunk("mine", speaker: "me", "I will send the specification by Wednesday noon.", at: 100),
                      chunk("hers", speaker: "maya", "I will review the design document on Tuesday.", at: 200),
                      chunk("none", speaker: "", "I will bring the salad tonight.", at: 300)]
        let outcome = RetrievalOutcome(query: q, knownTerms: [], unknownTerms: [], timeWindow: nil, hits: [], coverage: 0,
                                       headlineWeights: [:], corpusSize: 3, elapsedMs: 0)
        return TierTwoPlanner.plan(query: q, decision: RouteDecision(tier: .cloud, reason: "", signals: [], intent: .commitments),
                                   outcome: outcome, chunks: chunks, model: "m", mySpeakerId: me)
    }

    @Test func whatDidIPromiseIsAboutWhatTheyThemselvesSaidOnceTheirVoiceIsKnown() {
        let mine = plan("What did I promise people today?", me: "me")
        #expect(mine.snippets.map(\.chunkID) == ["mine"] && mine.selectionReason.contains("in your voice"))
    }

    @Test func otherQuestionsAndUnknownVoicesLeaveTheSelectionAlone() {
        for (q, me) in [("What did Maya promise today?", "me"), ("What did everyone promise today?", "me"), ("What did I promise people today?", nil)] as [(String, String?)] {
            let p = plan(q, me: me)
            #expect(Set(p.snippets.map(\.chunkID)) == ["mine", "hers", "none"], "\(q)")
            #expect(!p.selectionReason.contains("your voice"))
        }
    }

    @Test func firstPersonQuestionsAreRecognised() {
        for q in ["What did I promise?", "what do I owe people", "Which of my promises are due?", "tell me what I'll do", "what's mine to do"] {
            #expect(TierTwoPlanner.isFirstPerson(q), "\(q)")
        }
        for q in ["What did Maya promise?", "What did everyone commit to today?", "Summarize the day"] {
            #expect(!TierTwoPlanner.isFirstPerson(q), "\(q)")
        }
    }

    @Test func aPromiseKnowsWhoSaidIt() {
        let found = PromiseExtractor.extract(from: [chunk("c", speaker: "me", "I will send the spec by Friday.")])
        #expect(found.first?.speakerId == "me")
    }
}
