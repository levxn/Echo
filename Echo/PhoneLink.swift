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

    /// Answers a question the watch asked (quick-ask).
    var onAsk: ((String) async -> WatchAnswer)?

    init(model: PipelineModel) {
        self.model = model
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the watch to start replaying the day (the same as tapping Start day on it). Used by the demo driver.
    func sendDemoStart() {
        guard WCSession.default.isReachable else { Log.link.error("the watch isn't reachable, so it can't be started from here"); return }
        WCSession.default.sendMessage([Wire.typeKey: Wire.demoStart], replyHandler: nil) { error in
            Log.link.error("couldn't start the watch: \(error.localizedDescription)")
        }
    }

    /// Asks the watch to run quick-ask preset `index`, as if tapped (the demo driver uses this).
    func sendDemoQuickAsk(_ index: Int) {
        guard WCSession.default.isReachable else { Log.link.error("the watch isn't reachable, so it can't be asked from here"); return }
        WCSession.default.sendMessage([Wire.typeKey: Wire.demoQuickAsk, Wire.presetKey: index], replyHandler: nil) { error in
            Log.link.error("couldn't reach the watch: \(error.localizedDescription)")
        }
    }

    // MARK: Handling (main actor)

    private func handle(message: [String: Any]) async -> [String: Any] {
        switch message[Wire.typeKey] as? String {
        case Wire.session: return await handle(session: message)
        case Wire.ask:
            guard let question = message[Wire.questionKey] as? String, let onAsk else { return [Wire.okKey: false] }
            return await onAsk(question).dictionary
        default: return [Wire.okKey: false]
        }
    }

    private func handle(session message: [String: Any]) async -> [String: Any] {
        let recorded = message[Wire.recordedKey] as? Double ?? 0
        let total = message[Wire.totalKey] as? Double ?? 0
        if message[Wire.stateKey] as? String == "started" {
            await model.sessionStarted(total: total)
        } else {
            model.sessionFinished(recorded: recorded, expectedChunks: message[Wire.countKey] as? Int ?? 0)
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
        Task { @MainActor in reply(await self.handle(message: msg)) }
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
