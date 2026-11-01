import AVFoundation
import Foundation
import Observation

/// A recorded question, ready to send: AAC audio and how long it runs.
nonisolated struct QuestionClip: Sendable, Equatable {
    let audio: Data
    let seconds: Double
    /// Small enough for one WatchConnectivity message (the largest proven in this project is 60 KB).
    static let maxBytes = 40_000

    static func make(from segment: SpeechSegment) -> QuestionClip? {
        for bitRate in [20_000, 12_000] {
            if let data = AudioCodec.encodeAAC(samples: segment.samples, sampleRate: segment.sampleRate, bitRate: bitRate), data.count <= maxBytes {
                return QuestionClip(audio: data, seconds: segment.duration)
            }
        }
        return nil
    }
}

nonisolated enum QuestionRecordingError: Error, Equatable {
    case microphoneDenied, microphoneUnavailable, nothingHeard, encodeFailed

    var message: String {
        switch self {
        case .microphoneDenied: "Echo can't use the microphone. Turn it on in Settings."
        case .microphoneUnavailable: "The microphone isn't available right now."
        case .nothingHeard: "I didn't catch that. Tap the mic and try again."
        case .encodeFailed: "Couldn't prepare that recording. Try again."
        }
    }
}

/// Decides when a spoken question has ended: a second of silence after speech, or 8 seconds at most. A thin wrapper over
/// the stage-1 voice detector with settings for one short question instead of a day of conversation.
nonisolated final class QuestionEndpointer {
    static let frame = 480   // 30 ms at 16 kHz, what the detector takes
    static let config = VADConfig(hangoverFrames: 33, preRollSeconds: 0.4, minSegmentSeconds: 0.4, maxSegmentSeconds: 8)

    private let vad = EnergyVAD(config: QuestionEndpointer.config)
    private var pending: [Int16] = []
    /// 0...1, for a level meter.
    private(set) var level = 0.0
    var isSpeaking: Bool { vad.isSpeaking }

    /// Feed samples of any length. Returns the finished question as soon as it ends.
    func push(_ samples: [Int16]) -> SpeechSegment? {
        pending.append(contentsOf: samples)
        while pending.count >= Self.frame {
            let frame = Array(pending.prefix(Self.frame))
            pending.removeFirst(Self.frame)
            level = max(0, min(1, (EnergyVAD.db(of: frame[...]) + 60) / 45))
            if let segment = vad.push(frame) { return segment }
        }
        return nil
    }

    /// Ends the question now (the user tapped stop). Nil if no speech had begun.
    func finish() -> SpeechSegment? { vad.flush() }
}

/// The recorded questions that stand in for the microphone in a simulator.
nonisolated enum QuestionClips {
    static let count = 5

    /// `n` is 1...count.
    static func url(_ n: Int, in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "q\(n)", withExtension: "wav") ?? bundle.url(forResource: "q\(n)", withExtension: "wav", subdirectory: "Questions")
    }
}

/// Records one spoken question. On a device it listens to the microphone; in a simulator it plays a recorded question
/// through the same endpointer, and says so. Either way the result is a short AAC clip.
@MainActor
@Observable
final class QuestionRecorder {
    enum Source {
        case microphone
        case clip(URL)
    }

    enum Phase: Equatable { case idle, listening }

    private(set) var phase = Phase.idle
    /// 0...1 while listening.
    private(set) var level = 0.0
    /// True while the audio comes from a recorded clip, not a microphone.
    private(set) var simulated = false
    private var stopRequested = false

    /// The microphone on a device; in a simulator a recorded question, cycling through the five. `-real-mic` forces the
    /// microphone in a simulator (it uses your Mac's, if one is available).
    static func defaultSource(next index: Int, arguments: [String] = ProcessInfo.processInfo.arguments) -> Source {
        #if targetEnvironment(simulator)
        if !arguments.contains("-real-mic"), let url = QuestionClips.url((index % QuestionClips.count) + 1) { return .clip(url) }
        #endif
        return .microphone
    }

    /// Ends the recording early, as if the question had finished.
    func stop() { stopRequested = true }

    func record(_ source: Source, maxWait: Double = 10) async -> Result<QuestionClip, QuestionRecordingError> {
        guard phase == .idle else { return .failure(.microphoneUnavailable) }
        phase = .listening
        stopRequested = false
        level = 0
        defer { phase = .idle; level = 0 }
        let segment: SpeechSegment?
        switch source {
        case .clip(let url):
            simulated = true
            switch await play(url) {
            case .success(let s): segment = s
            case .failure(let e): return .failure(e)
            }
        case .microphone:
            simulated = false
            switch await listen(maxWait: maxWait) {
            case .success(let s): segment = s
            case .failure(let e): return .failure(e)
            }
        }
        guard let segment else { return .failure(.nothingHeard) }
        guard let clip = QuestionClip.make(from: segment) else { return .failure(.encodeFailed) }
        return .success(clip)
    }

    // MARK: Recorded clip (simulators)

    private func play(_ url: URL) async -> Result<SpeechSegment?, QuestionRecordingError> {
        guard let wav = try? WAV.read(url), wav.sampleRate == 16_000 else { return .failure(.microphoneUnavailable) }
        let endpointer = QuestionEndpointer()
        var cursor = 0
        while cursor + QuestionEndpointer.frame <= wav.samples.count, !stopRequested {
            if let segment = endpointer.push(Array(wav.samples[cursor..<cursor + QuestionEndpointer.frame])) { return .success(segment) }
            cursor += QuestionEndpointer.frame
            level = endpointer.level
            try? await Task.sleep(for: .milliseconds(10))   // faster than real time, but slow enough to see the meter move
        }
        return .success(endpointer.finish())
    }

    // MARK: Microphone (devices)

    private func listen(maxWait: Double) async -> Result<SpeechSegment?, QuestionRecordingError> {
        guard await AVAudioApplication.requestRecordPermission() else { return .failure(.microphoneDenied) }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch { return .failure(.microphoneUnavailable) }
        defer { try? session.setActive(false, options: .notifyOthersOnDeactivation) }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0,
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else { return .failure(.microphoneUnavailable) }

        let tap = MicTap(converter: converter, outFormat: outFormat)
        input.installTap(onBus: 0, bufferSize: 2_048, format: inFormat) { buffer, _ in tap.process(buffer) }
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            return .failure(.microphoneUnavailable)
        }
        defer { engine.stop(); input.removeTap(onBus: 0) }

        let started = Date()
        let segment: SpeechSegment? = await withCheckedContinuation { continuation in
            let gate = OneShot()
            tap.onSegment = { segment in if gate.first() { continuation.resume(returning: segment) } }
            Task { @MainActor in
                while !tap.isDone {
                    try? await Task.sleep(for: .milliseconds(80))
                    level = tap.level
                    if stopRequested || Date().timeIntervalSince(started) > maxWait {
                        if gate.first() { continuation.resume(returning: tap.finish()) }
                        return
                    }
                }
            }
        }
        return .success(segment)
    }
}

/// Receives microphone buffers on the audio thread, converts them to 16 kHz mono and hands them to an endpointer.
private final class MicTap: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let outFormat: AVAudioFormat
    private let endpointer = QuestionEndpointer()
    private let lock = NSLock()
    private var done = false
    private var currentLevel = 0.0
    var onSegment: (@Sendable (SpeechSegment) -> Void)?

    init(converter: AVAudioConverter, outFormat: AVAudioFormat) {
        self.converter = converter
        self.outFormat = outFormat
    }

    var isDone: Bool { lock.lock(); defer { lock.unlock() }; return done }
    var level: Double { lock.lock(); defer { lock.unlock() }; return currentLevel }

    func finish() -> SpeechSegment? {
        lock.lock(); defer { lock.unlock() }
        done = true
        return endpointer.finish()
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.int16ChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        lock.lock()
        if done { lock.unlock(); return }
        let segment = endpointer.push(samples)
        currentLevel = endpointer.level
        if segment != nil { done = true }
        lock.unlock()
        if let segment { onSegment?(segment) }
    }
}
