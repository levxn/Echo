import Foundation
import os

/// Runs each received chunk through stage-2 VAD and on-device ASR, one at a time, updating the model
/// as it goes so the UI can show progress.
@MainActor
final class Pipeline {
    /// Minimum "speech" confidence for stage 2 to keep a chunk. Calibrated against the demo manifest.
    static let speechThreshold = 0.5
    /// Padding kept around the detected speech span when trimming.
    static let spanPadding = 0.3

    private let model: PipelineModel
    /// Tells voices apart (set by the app; tests that don't care leave it nil).
    var voices: VoiceBookModel?
    /// Honors "off the record" (set by the app; tests that don't care leave it nil).
    var privacy: RecordingPrivacy?
    /// Surfaces promises as they are said (set by the app).
    var watcher: PromiseWatcher?
    private var pending: [ChunkRecord] = []
    private var running = false

    init(model: PipelineModel) { self.model = model }

    func enqueue(_ record: ChunkRecord) {
        pending.append(record)
        if !running { Task { await drain() } }
    }

    private func drain() async {
        running = true
        defer { running = false }
        while !pending.isEmpty {
            await process(pending.removeFirst())
        }
    }

    private func process(_ record: ChunkRecord) async {
        let url = await model.store.url(for: record.audioFile)
        var chunk = record

        // Stage 2: is there really speech in here, and where?
        do {
            let result = try await Stage2VAD.analyze(url: url)
            chunk.speechConfidence = result.maxSpeech
            guard let span = result.speechSpan(threshold: Self.speechThreshold) else {
                chunk.status = .dropped
                chunk.confirmedSeconds = 0
                model.put(chunk)
                Log.pipe.info("chunk \(chunk.index) dropped (speech \(result.maxSpeech, format: .fixed(precision: 2)))")
                return
            }
            let lo = max(0, span.lowerBound - Self.spanPadding)
            let hi = min(chunk.duration, span.upperBound + Self.spanPadding)
            chunk.confirmedSeconds = max(0, hi - lo)
            chunk.status = .vad
            // Whose voice is it? Worked out on the phone from the audio, off the main thread.
            if let voices {
                let print = await Task.detached(priority: .utility) { AudioDecoder.voicePrint(url: url) }.value
                if let id = await voices.identify(chunkID: chunk.id, print: print) { chunk.speakerId = id }
            }
            model.put(chunk)
        } catch {
            Log.pipe.error("stage 2 failed for chunk \(chunk.index): \(error.localizedDescription)")
            chunk.status = .failed
            model.put(chunk)
            return
        }

        // ASR, fully on-device.
        do {
            let text = try await OnDeviceASR.transcribe(url: url)
            // "Off the record": the command and whatever is said while it is off are understood only to listen for
            // "back on the record", then dropped here: no transcript, no search entry, no audio.
            if let privacy, privacy.decide(transcript: text) != .keep {
                chunk.status = .dropped
                chunk.transcript = nil
                chunk.confirmedSeconds = 0
                model.put(chunk)
                await model.store.removeAudio(named: chunk.audioFile)
                Log.pipe.info("chunk \(chunk.index) dropped: off the record")
                return
            }
            chunk.transcript = text
            chunk.status = .asr
            model.put(chunk)
            Log.pipe.info("chunk \(chunk.index) ASR: \(text)")
        } catch {
            Log.pipe.error("ASR failed for chunk \(chunk.index): \(error.localizedDescription)")
            chunk.status = .failed
            model.put(chunk)
            return
        }

        // Index for search: normalized text into FTS5, mean word vector onto the chunk row.
        if let text = chunk.transcript { await index(chunkID: chunk.id, text: text) }

        chunk.status = .stored
        model.put(chunk)
        watcher?.chunkStored(chunk)
    }

    private func index(chunkID: String, text: String) async {
        await model.store.index(id: chunkID, normalizedText: TextNormalizer.normalized(text),
                                embedding: Embedder.vector(for: text))
    }

    /// Indexes chunks that were stored before the search index existed.
    func backfillIndex() async {
        let indexed = await model.store.indexedIDs()
        for chunk in model.chunks where chunk.status == .stored && !indexed.contains(chunk.id) {
            if let text = chunk.transcript { await index(chunkID: chunk.id, text: text) }
        }
    }
}
