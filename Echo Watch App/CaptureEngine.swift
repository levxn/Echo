import Foundation
import Observation
import os
import WatchKit

/// Hands each speech segment to the link. On a watch it listens to the microphone (all day, kept running by a workout session);
/// in a simulator it replays a bundled day through the same stage-1 VAD as if it were the microphone. Everything after
/// the detector is the same either way.
@MainActor
@Observable
final class CaptureEngine {
    enum Phase { case idle, running, paused, finished }

    private(set) var phase: Phase = .idle
    private(set) var progress = 0.0              // 0...1 through the recording
    private(set) var speaking = false
    private(set) var level = 0.0                 // 0...1, for the mic ring
    private(set) var captured = 0                // segments produced by the VAD
    private(set) var keptSeconds = 0.0
    private(set) var recordedSeconds = 0.0
    private(set) var totalSeconds = 0.0

    /// How many times faster than real time the recording is replayed.
    var speed = 20.0

    let link: WatchLink
    private var task: Task<Void, Never>?
    private let microphone = MicrophoneSource()
    private let keepAlive: any BackgroundKeepAlive = WorkoutBackgroundCapture()
    /// Why the microphone couldn't be used, to show on the watch.
    private(set) var problem: String?

    init(link: WatchLink) { self.link = link }

    /// A real watch listens to its microphone; a simulator replays the recorded day (`-live-mic` forces the microphone there).
    static func listensLive(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if targetEnvironment(simulator)
        return arguments.contains("-live-mic")
        #else
        return true
        #endif
    }

    private var liveSegmenter: LiveSegmenter?
    private var liveOrigin = Date()
    private var index = 0

    private let location = WatchLocation()
    private var lastAnnounce = Date()

    /// When the phone says to announce recording, the watch buzzes as it starts and every ten minutes after, so people
    /// nearby aren't unaware that it is listening.
    private func announceIfDue(starting: Bool = false) {
        guard UserDefaults.standard.bool(forKey: "echo.announce") else { return }
        if starting || Date().timeIntervalSince(lastAnnounce) >= 600 {
            lastAnnounce = Date()
            WKInterfaceDevice.current().play(.notification)
        }
    }

    /// 0 = a day for today; -7 = the recording of a week ago (a different day, kept alongside today's on the phone).
    private var dayOffset = 0

    /// The primary button: listen live, or replay the day.
    func begin(dayOffset: Int = 0) {
        if Self.listensLive() && dayOffset == 0 { startLive() } else { start(dayOffset: dayOffset) }
    }

    func start(dayOffset: Int = 0) {
        guard phase == .idle || phase == .finished else { return }
        self.dayOffset = dayOffset
        captured = 0; keptSeconds = 0; recordedSeconds = 0; progress = 0
        link.resetCounters()
        phase = .running
        task = Task { await run() }
    }

    func togglePause() {
        switch phase {
        case .running where isLive: stopLive()
        case .running: phase = .paused
        case .paused: phase = .running
        default: break
        }
    }

    // MARK: Listening live

    func startLive() {
        guard phase == .idle || phase == .finished || phase == .paused, liveSegmenter == nil else { return }
        captured = 0; keptSeconds = 0; recordedSeconds = 0; progress = 0; problem = nil
        link.resetCounters()
        phase = .running
        task = Task { await runLive() }
    }

    private func runLive() async {
        let segmenter = LiveSegmenter()
        liveSegmenter = segmenter
        liveOrigin = Date()
        let stayingAwake = await keepAlive.begin()
        Log.app.info("listening live; background capture \(stayingAwake ? "on" : "off")")
        // Segments arrive on the audio thread; they are passed to the main actor in order.
        let (segments, continuation) = AsyncStream<SpeechSegment>.makeStream()
        liveContinuation = continuation
        do {
            try await microphone.start { samples in
                for segment in segmenter.push(samples) { continuation.yield(segment) }
            }
        } catch {
            liveContinuation = nil
            problem = (error as? MicrophoneSource.Failure) == .denied ? "Microphone is off for Echo" : "Microphone unavailable"
            continuation.finish()
            liveSegmenter = nil
            await keepAlive.end()
            phase = .idle
            return
        }
        await link.sendSession(state: "started", recorded: 0, total: 0, dayOffset: 0, live: true)
        announceIfDue(starting: true)
        location.start()
        let origin = liveOrigin

        let meter = Task { @MainActor in
            while !Task.isCancelled {
                speaking = segmenter.isSpeaking
                level = segmenter.level
                recordedSeconds = Date().timeIntervalSince(origin)
                link.recordedSoFar = recordedSeconds
                announceIfDue()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        for await segment in segments { emitLive(segment) }
        meter.cancel()
        // Listening stopped: whatever was being said is kept too.
        if let last = segmenter.finish() { emitLive(last) }
        location.stop()
        speaking = false; level = 0
        liveSegmenter = nil
        await keepAlive.end()
        phase = .finished
        await link.sendSession(state: "finished", recorded: recordedSeconds, total: recordedSeconds, count: link.enqueuedTotal)
    }

    private var liveContinuation: AsyncStream<SpeechSegment>.Continuation?

    private func emitLive(_ seg: SpeechSegment) {
        let wall = LiveClock.wallSeconds(origin: liveOrigin, offset: seg.startSeconds)
        let meta = ChunkMeta(id: UUID().uuidString, index: LiveClock.index(wallSeconds: wall), wallStart: wall, fileOffset: seg.startSeconds,
                             duration: seg.duration, sampleRate: seg.sampleRate, peakDb: seg.peakDb, meanDb: seg.meanDb,
                             sampleCount: seg.samples.count, coordinate: location.latest?.coarse())
        captured += 1
        keptSeconds += seg.duration
        link.enqueue(meta, samples: seg.samples)
    }

    func stopLive() {
        guard liveSegmenter != nil else { return }
        microphone.stop()
        liveContinuation?.finish()   // ends the stream of segments, which finishes the session above
        liveContinuation = nil
    }

    /// True once the last capture was from the microphone (for the title after it stops).
    var wasLive: Bool { CaptureEngine.listensLive() }

    /// True while listening to the microphone (as opposed to replaying a day).
    var isLive: Bool { liveSegmenter != nil }

    private func run() async {
        let name = dayOffset < 0 ? "demo_day_prev" : "demo_day"
        guard let wavURL = Bundle.main.url(forResource: name, withExtension: "wav"),
              let manifestURL = Bundle.main.url(forResource: name, withExtension: "json"),
              let manifest = try? DemoManifest.load(from: manifestURL),
              let (samples, rate) = try? WAV.read(wavURL) else {
            Log.app.error("demo audio missing from bundle")
            phase = .idle
            return
        }
        let clock = DemoClock(manifest: manifest)
        // A recording that says where it happened is replayed with those places; otherwise the watch's own location is used.
        let scripted = manifest.scenes.contains { $0.place != nil }
        if !scripted { location.start() }
        defer { if !scripted { location.stop() } }
        let vad = EnergyVAD()
        let frame = vad.config.frameSamples
        totalSeconds = Double(samples.count) / Double(rate)
        await link.sendSession(state: "started", recorded: 0, total: totalSeconds, dayOffset: dayOffset)
        announceIfDue(starting: true)

        let tickSeconds = 0.05
        let framesPerTick = max(1, Int((tickSeconds * speed) / (Double(frame) / Double(rate))))
        var cursor = 0
        index = 0

        func emit(_ seg: SpeechSegment) {
            let meta = ChunkMeta(
                id: UUID().uuidString, index: index,
                wallStart: clock.wallSeconds(forOffset: seg.startSeconds),
                fileOffset: seg.startSeconds, duration: seg.duration, sampleRate: seg.sampleRate,
                peakDb: seg.peakDb, meanDb: seg.meanDb, sampleCount: seg.samples.count,
                coordinate: (scripted ? manifest.place(atOffset: seg.startSeconds) : location.latest)?.coarse()
            )
            index += 1
            captured += 1
            keptSeconds += seg.duration
            link.enqueue(meta, samples: seg.samples)
            Log.vad.info("segment \(meta.index) @\(seg.startSeconds, format: .fixed(precision: 1))s dur=\(seg.duration, format: .fixed(precision: 1))s peak=\(seg.peakDb, format: .fixed(precision: 1))dB")
        }

        while cursor + frame <= samples.count, !Task.isCancelled {
            if phase == .paused { try? await Task.sleep(for: .milliseconds(100)); continue }
            for _ in 0..<framesPerTick where cursor + frame <= samples.count {
                if let seg = vad.push(Array(samples[cursor..<cursor + frame])) { emit(seg) }
                cursor += frame
            }
            announceIfDue()
            recordedSeconds = Double(cursor) / Double(rate)
            progress = recordedSeconds / totalSeconds
            speaking = vad.isSpeaking
            level = max(0, min(1, (vad.currentDb + 60) / 45))
            link.recordedSoFar = recordedSeconds
            try? await Task.sleep(for: .milliseconds(Int(tickSeconds * 1000)))
        }
        if let seg = vad.flush() { emit(seg) }
        speaking = false
        level = 0
        progress = 1
        recordedSeconds = totalSeconds
        link.recordedSoFar = totalSeconds
        phase = .finished
        Log.vad.info("replay finished: \(self.captured) segments, kept \(self.keptSeconds, format: .fixed(precision: 1))s of \(self.totalSeconds, format: .fixed(precision: 1))s")
        await link.sendSession(state: "finished", recorded: totalSeconds, total: totalSeconds, count: link.enqueuedTotal)
    }
}
