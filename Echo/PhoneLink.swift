import Foundation
import Observation
import os
import WatchConnectivity

/// Receives bundles of AAC chunks from the watch, stores each as an m4a file, and hands the new
/// records to the pipeline.
@MainActor
final class PhoneLink: NSObject, WCSessionDelegate {
    private let model: PipelineModel

    /// Called after a chunk is stored as `.received`.
    var onChunkReceived: ((ChunkRecord) -> Void)?

    init(model: PipelineModel) {
        self.model = model
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Handling (main actor)

    private func handle(session message: [String: Any]) async -> [String: Any] {
        guard message[Wire.typeKey] as? String == Wire.session else { return [Wire.okKey: false] }
        let recorded = message[Wire.recordedKey] as? Double ?? 0
        let total = message[Wire.totalKey] as? Double ?? 0
        if message[Wire.stateKey] as? String == "started" {
            await model.sessionStarted(total: total)
        } else {
            model.sessionFinished(recorded: recorded)
        }
        return [Wire.okKey: true]
    }

    private func handle(bundle data: Data) async -> Bool {
        guard let (entries, recorded) = ChunkBundle.decode(data) else {
            Log.link.error("undecodable bundle (\(data.count) bytes)")
            return false
        }
        model.updateRecorded(recorded)
        for entry in entries { await store(entry) }
        Log.link.info("received bundle: \(entries.count) chunks, \(data.count) bytes")
        return true
    }

    private func store(_ entry: ChunkBundle.Entry) async {
        let meta = entry.meta
        guard model.record(id: meta.id) == nil else { return }   // retry after a lost ack
        let file = "\(meta.id).m4a"
        do {
            try await model.store.write(audio: entry.audio, named: file)
        } catch {
            Log.link.error("write audio failed: \(error.localizedDescription)")
            return
        }
        let record = ChunkRecord(
            id: meta.id, index: meta.index, wallStart: meta.wallStart, fileOffset: meta.fileOffset,
            duration: meta.duration, peakDb: meta.peakDb, meanDb: meta.meanDb, audioFile: file,
            status: .received, speechConfidence: nil, confirmedSeconds: 0, transcript: nil
        )
        model.put(record)
        onChunkReceived?(record)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.model.setReachable(reachable) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.model.setReachable(reachable) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        nonisolated(unsafe) let msg = message
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in reply(await self.handle(session: msg)) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                             replyHandler: @escaping (Data) -> Void) {
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let ok = await self.handle(bundle: messageData)
            reply(Data([ok ? 1 : 0]))
        }
    }
}
