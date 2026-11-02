import AVFoundation
import Foundation
import Testing
@testable import Echo

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private struct QuestionManifest: Decodable {
    struct Entry: Decodable { let file: String; let text: String; let speechStart: Double; let speechEnd: Double; let duration: Double }
    let questions: [Entry]

    static func load() throws -> QuestionManifest {
        try JSONDecoder().decode(QuestionManifest.self, from: Data(contentsOf: repoRoot.appending(path: "Shared/Questions/questions.json")))
    }
}

struct VoiceTests {
    private func samples(_ file: String) throws -> [Int16] {
        try WAV.read(repoRoot.appending(path: "Shared/Questions/\(file)")).samples
    }

    /// Feeds a clip in the odd-sized pieces a microphone delivers, and reports when the question was judged finished.
    private func runEndpointer(_ pcm: [Int16], piece: Int = 1_600) -> (segment: SpeechSegment?, fedSeconds: Double) {
        let endpointer = QuestionEndpointer()
        var start = 0
        while start < pcm.count {
            let end = min(pcm.count, start + piece)
            if let segment = endpointer.push(Array(pcm[start..<end])) { return (segment, Double(end) / 16_000) }
            start = end
        }
        return (endpointer.finish(), Double(pcm.count) / 16_000)
    }

    // MARK: The recorded questions

    @Test func fiveRecordedQuestionsExistWithTheirText() throws {
        let manifest = try QuestionManifest.load()
        #expect(manifest.questions.count == QuestionClips.count)
        #expect(manifest.questions.map(\.text) == ["When is the plumber coming?", "What did Mister Brennan say about the lease?",
                                                  "Where is Priya going in March?", "What did I promise people today?", "Summarize my day"])
        for entry in manifest.questions {
            let pcm = try samples(entry.file)
            #expect(abs(Double(pcm.count) / 16_000 - entry.duration) < 0.05, "\(entry.file) matches its manifest")
        }
    }

    @Test func theClipsAreBundledIntoTheApp() {
        for n in 1...QuestionClips.count { #expect(QuestionClips.url(n) != nil, "q\(n).wav is in the app bundle") }
    }

    // MARK: Knowing when a question has ended

    @Test func theQuestionEndsAboutASecondAfterTheSpeakerStops() throws {
        for entry in try QuestionManifest.load().questions {
            let pcm = try samples(entry.file)
            let (segment, fedSeconds) = runEndpointer(pcm)
            let seg = try #require(segment, "\(entry.file) produced a question")
            #expect(fedSeconds < entry.duration - 0.3, "\(entry.file) stopped listening before the end of the recording")
            #expect(fedSeconds - entry.speechEnd < 1.4, "\(entry.file) waited \(fedSeconds - entry.speechEnd) s after the speech")
            #expect(fedSeconds >= entry.speechEnd, "it does not cut the speaker off")
            #expect(seg.duration >= entry.speechEnd - entry.speechStart, "all of the speech is in the segment")
            #expect(seg.duration <= 8.5)
        }
    }

    @Test func silenceAloneIsNotAQuestion() {
        let quiet = (0..<(16_000 * 10)).map { _ in Int16.random(in: -25...25) }
        let (segment, _) = runEndpointer(quiet)
        #expect(segment == nil)
    }

    @Test func aLongRamblingIsCutAtEightSeconds() {
        // Half a second of room noise, then twelve seconds of loud, unbroken sound (the detector learns the room first).
        let room = (0..<8_000).map { _ in Int16.random(in: -25...25) }
        let tone = (0..<(16_000 * 12)).map { Int16(sin(Double($0) * 0.2) * 4_000) }
        let (segment, fed) = runEndpointer(room + tone)
        let seg = segment
        #expect(seg != nil && seg!.duration <= 8.6 && seg!.duration >= 7.5, "capped at about 8 s, got \(seg?.duration ?? 0)")
        #expect(fed < 9.5)
    }

    @Test func stoppingEarlyKeepsWhatWasSaid() throws {
        let pcm = try samples("q4.wav")
        let endpointer = QuestionEndpointer()
        var fed = 0
        while fed < 16_000 * 1 + 8_000 {   // 1.5 s in: speech has begun but not ended
            #expect(endpointer.push(Array(pcm[fed..<fed + 480])) == nil)
            fed += 480
        }
        #expect(endpointer.isSpeaking)
        #expect(endpointer.finish() != nil, "tapping stop returns the question so far")
        #expect(QuestionEndpointer().finish() == nil, "nothing was said")
    }

    // MARK: Ready to send

    @Test func everyRecordedQuestionFitsInOneMessage() throws {
        for entry in try QuestionManifest.load().questions {
            let seg = try #require(runEndpointer(try samples(entry.file)).segment)
            let clip = try #require(QuestionClip.make(from: seg), "\(entry.file) encodes")
            #expect(clip.audio.count <= QuestionClip.maxBytes && clip.audio.count > 1_000, "\(entry.file): \(clip.audio.count) bytes")
            #expect(clip.audio.count < Wire.maxMessage)
            #expect(abs(clip.seconds - seg.duration) < 0.01)
        }
    }

    @MainActor
    @Test func theRecorderPlaysARecordedQuestionAndSaysItIsSimulated() async throws {
        let url = repoRoot.appending(path: "Shared/Questions/q1.wav")
        let recorder = QuestionRecorder()
        #expect(recorder.phase == .idle)
        let result = await recorder.record(.clip(url))
        let clip = try result.get()
        #expect(clip.seconds > 1 && clip.seconds < 4 && !clip.audio.isEmpty)
        #expect(recorder.simulated, "a recorded clip is never passed off as the microphone")
        #expect(recorder.phase == .idle && recorder.level == 0)
    }

    @MainActor
    @Test func aMissingClipIsAnErrorNotACrash() async {
        let recorder = QuestionRecorder()
        let result = await recorder.record(.clip(URL(fileURLWithPath: "/nonexistent/q.wav")))
        #expect(result == .failure(.microphoneUnavailable))
    }

    @MainActor
    @Test func stoppingTheRecorderEndsItEarly() async throws {
        let recorder = QuestionRecorder()
        let url = repoRoot.appending(path: "Shared/Questions/q2.wav")   // 2.5 s of speech
        let task = Task { await recorder.record(.clip(url)) }
        // Wait until the speaker is actually heard (the meter moves), then stop, rather than guessing a time.
        for _ in 0..<600 where recorder.level < 0.3 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(recorder.level >= 0.3, "speech was heard")
        try await Task.sleep(for: .milliseconds(600))   // a moment of speech, as a person tapping stop would allow
        recorder.stop()
        let clip = try await task.value.get()
        #expect(clip.seconds < 2.4, "it returned what had been said so far, not the whole question (\(clip.seconds) s)")
    }

    @MainActor
    @Test func theSimulatorCyclesThroughTheFiveQuestions() {
        func name(_ i: Int) -> String? {
            if case .clip(let url) = QuestionRecorder.defaultSource(next: i, arguments: []) { return url.lastPathComponent }
            return nil
        }
        #if targetEnvironment(simulator)
        #expect((0..<7).map(name) == ["q1.wav", "q2.wav", "q3.wav", "q4.wav", "q5.wav", "q1.wav", "q2.wav"])
        if case .microphone = QuestionRecorder.defaultSource(next: 0, arguments: ["-real-mic"]) {} else { Issue.record("-real-mic should force the microphone") }
        #endif
    }

    // MARK: Understanding it, on the phone

    private func audioBlob() -> Data { Data("not really audio".utf8) }

    @Test func aHeardQuestionIsReturnedTidyAndTheAudioIsDeleted() async {
        let seen = SeenFile()
        let transcriber = QuestionTranscriber(recognize: { url in
            seen.record(url)
            return "  What did I promise people today? \n"
        })
        let result = await transcriber.transcribe(audio: audioBlob())
        #expect(result == .heard("What did I promise people today?"))
        #expect(seen.existedWhenRead && !seen.stillThere, "the clip existed for the recognizer and is gone afterwards")
    }

    @Test func eachWayItCanGoWrongHasAKindMessageAndAReason() async {
        func outcome(_ recognize: @escaping @Sendable (URL) async throws -> String) async -> QuestionTranscription {
            await QuestionTranscriber(timeout: 1, recognize: recognize).transcribe(audio: audioBlob())
        }
        #expect(await outcome { _ in "   " } == .nothingHeard, "an empty transcript is not a question")
        #expect(await outcome { _ in throw OnDeviceASR.ASRError.notAuthorized } == .speechOff)
        #expect(await outcome { _ in throw OnDeviceASR.ASRError.unavailable } == .unavailable)
        #expect(await outcome { _ in throw NSError(domain: "kAFAssistantErrorDomain", code: 1110) } == .nothingHeard, "'no speech detected' arrives as an error")
        let all: [QuestionTranscription] = [.heard("x"), .nothingHeard, .speechOff, .unavailable, .timedOut]
        #expect(all.dropFirst().allSatisfy { $0.message != nil } && all[0].message == nil)
        #expect(Set(all.map(\.reason)).count == all.count)
    }

    @Test func aRecognizerThatNeverAnswersTimesOutInsteadOfHanging() async {
        let started = Date()
        let result = await QuestionTranscriber(timeout: 0.3, recognize: { _ in
            try await Task.sleep(for: .seconds(30))
            return "too late"
        }).transcribe(audio: audioBlob())
        #expect(result == .timedOut)
        #expect(Date().timeIntervalSince(started) < 10, "gave up after the timeout, not after 30 s")
    }

    @Test func theTimeoutHelperPassesThroughResultsAndErrors() async throws {
        #expect(try await Timeout.run(seconds: 1) { 42 } == 42)
        struct Boom: Error {}
        await #expect(throws: Boom.self) { try await Timeout.run(seconds: 1) { throw Boom() } as Int }
        let gate = OneShot()
        #expect(gate.first() && !gate.first() && !gate.first())
    }
}

/// Remembers a file the recognizer was handed, and whether it existed then.
private final class SeenFile: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?
    private var existed = false

    func record(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        self.url = url
        existed = FileManager.default.fileExists(atPath: url.path)
    }

    var existedWhenRead: Bool { lock.lock(); defer { lock.unlock() }; return existed }
    var stillThere: Bool { lock.lock(); defer { lock.unlock() }; return url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }
}
