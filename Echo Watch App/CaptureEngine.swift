import Foundation
import Observation
import os

/// Replays the bundled demo day through the stage-1 VAD as if it were a live microphone,
/// and hands each speech segment to the link. In a production build the frame source would be
/// an AVAudioEngine tap; everything after `push(frame)` stays the same.
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

    init(link: WatchLink) { self.link = link }

    func start() {
        guard phase == .idle || phase == .finished else { return }
        captured = 0; keptSeconds = 0; recordedSeconds = 0; progress = 0
        link.resetCounters()
        phase = .running
        task = Task { await run() }
    }

    func togglePause() {
        switch phase {
        case .running: phase = .paused
        case .paused: phase = .running
        default: break
        }
    }

    private func run() async {
        guard let wavURL = Bundle.main.url(forResource: "demo_day", withExtension: "wav"),
              let manifestURL = Bundle.main.url(forResource: "demo_day", withExtension: "json"),
              let manifest = try? DemoManifest.load(from: manifestURL),
              let (samples, rate) = try? WAV.read(wavURL) else {
            Log.app.error("demo audio missing from bundle")
            phase = .idle
            return
        }
        let clock = DemoClock(manifest: manifest)
        let vad = EnergyVAD()
        let frame = vad.config.frameSamples
        totalSeconds = Double(samples.count) / Double(rate)
        await link.sendSession(state: "started", recorded: 0, total: totalSeconds)

        let tickSeconds = 0.05
        let framesPerTick = max(1, Int((tickSeconds * speed) / (Double(frame) / Double(rate))))
        var cursor = 0
        var index = 0

        func emit(_ seg: SpeechSegment) {
            let meta = ChunkMeta(
                id: UUID().uuidString, index: index,
                wallStart: clock.wallSeconds(forOffset: seg.startSeconds),
                fileOffset: seg.startSeconds, duration: seg.duration, sampleRate: seg.sampleRate,
                peakDb: seg.peakDb, meanDb: seg.meanDb, sampleCount: seg.samples.count
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
