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

    /// The watch changed the listening mode or hours.
    var onListenSettings: ((ListeningSettings) -> Void)?

    /// Handles the watch's requests: questions, recorded questions to understand, and the recent history.
    var requests: WatchRequests?

    init(model: PipelineModel) {
        self.model = model
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Tells the watch a promise was just heard. False if the watch can't be reached right now.
    @discardableResult
    func sendPromiseCaught(_ promise: Promise) -> Bool {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return false }
        WCSession.default.sendMessage([Wire.typeKey: Wire.promiseCaught, Wire.idKey: promise.id, Wire.textKey: promise.sentence,
                                       Wire.dueKey: promise.due ?? ""], replyHandler: nil) { error in
            Log.link.error("couldn't tell the watch about a promise: \(error.localizedDescription)")
        }
        return true
    }

    /// Set by the app: answers a question that began "Hey Echo" and sends the answer to the watch.
    var wakeQuestion: ((String) -> Void)?

    /// Shows the watch the answer to a question that began "Hey Echo". Queued for later if the watch isn't reachable now.
    func sendWakeAnswer(question: String, answer: WatchAnswer) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let message: [String: Any] = [Wire.typeKey: Wire.wakeAnswer, Wire.questionKey: question, Wire.textKey: answer.text,
                                      Wire.sourceKey: answer.source.rawValue, Wire.speakKey: answer.speak]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: nil) { error in Log.link.error("couldn't send the answer to the watch: \(error.localizedDescription)") }
        } else {
            WCSession.default.transferUserInfo(message)
        }
    }

    /// Tells the watch whether to announce that it is listening. Delivered whenever the watch next wakes, even if it is away now.
    func sendSettings(announce: Bool) { sendContext([Wire.announceKey: announce]) }

    /// The complication's data: the same application context, so it arrives whenever the watch next wakes.
    func sendWidget(_ snapshot: Data) { sendContext([Wire.widgetKey: snapshot]) }

    /// An application context replaces the previous one, so everything the watch should know is kept together and re-sent.
    private var context: [String: Any] = [:]
    private func sendContext(_ patch: [String: Any]) {
        context.merge(patch) { _, new in new }
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        try? WCSession.default.updateApplicationContext(context)
    }

    /// Tells the watch the listening mode and hours (kept until it next wakes, so it can't be missed).
    func sendListening(_ settings: ListeningSettings) { sendContext([Wire.listenSettings: settings.dictionary]) }

    /// Asks the watch to start or stop listening now ("start" or "stop"). False if the watch can't be reached: a listening session
    /// can only be started by a watch app that is running.
    @discardableResult
    func sendListenCommand(_ command: String) -> Bool {
        guard WCSession.isSupported(), WCSession.default.isReachable else { return false }
        WCSession.default.sendMessage([Wire.typeKey: Wire.listenCommand, Wire.commandKey: command], replyHandler: nil) { error in
            Log.link.error("couldn't send \(command) to the watch: \(error.localizedDescription)")
        }
        return true
    }

    /// Asks the watch to start replaying the day (the same as tapping its listen button). Used by the demo driver.
    func sendDemoStart(dayOffset: Int = 0) {
        guard WCSession.default.isReachable else { Log.link.error("the watch isn't reachable, so it can't be started from here"); return }
        WCSession.default.sendMessage([Wire.typeKey: Wire.demoStart, Wire.dayOffsetKey: dayOffset], replyHandler: nil) { error in
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

    /// Asks the watch to ask recorded question `clip` (1...5) by voice, as if its mic had been tapped (the demo driver uses this).
    func sendDemoVoiceAsk(_ clip: Int) {
        guard WCSession.default.isReachable else { Log.link.error("the watch isn't reachable, so it can't be asked from here"); return }
        WCSession.default.sendMessage([Wire.typeKey: Wire.demoVoiceAsk, Wire.presetKey: clip], replyHandler: nil) { error in
            Log.link.error("couldn't reach the watch: \(error.localizedDescription)")
        }
    }

    // MARK: Handling (main actor)

    private func handle(message: [String: Any]) async -> [String: Any] {
        switch message[Wire.typeKey] as? String {
        case Wire.session: return await handle(session: message)
        default: return await requests?.handle(message) ?? [Wire.okKey: false]
        }
    }

    private func handle(session message: [String: Any]) async -> [String: Any] {
        let recorded = message[Wire.recordedKey] as? Double ?? 0
        let total = message[Wire.totalKey] as? Double ?? 0
        if message[Wire.stateKey] as? String == "started" {
            let offset = message[Wire.dayOffsetKey] as? Int ?? 0
            await model.sessionStarted(total: total, dayId: DayID.id(offset: offset, from: model.now()), keepExisting: message[Wire.liveKey] as? Bool ?? false)
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
            status: .received, speechConfidence: nil, confirmedSeconds: 0, transcript: nil, dayId: model.activeDayId,
            coordinate: meta.coordinate
        )
        model.put(record)
        onChunkReceived?(record)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        let context = session.receivedApplicationContext
        Task { @MainActor in
            self.model.setReachable(reachable)
            self.apply(context: context)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let context = applicationContext
        Task { @MainActor in self.apply(context: context) }
    }

    private func apply(context: [String: Any]) {
        if let dictionary = context[Wire.listenSettings] as? [String: Any], let settings = ListeningSettings(dictionary: dictionary) { onListenSettings?(settings) }
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
