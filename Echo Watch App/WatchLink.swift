import WidgetKit
import Foundation
import Observation
import os
import WatchConnectivity
import WatchKit

/// Lets exactly one of several racing callbacks (reply, error, timeout) resume a continuation.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false
    func first() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if used { return false }
        used = true
        return true
    }
}

/// Streams speech chunks to the phone. Chunks are AAC-encoded and bundled into messages of at most
/// `Wire.maxMessage` bytes; the queue drains one message at a time and retries while the phone is
/// unreachable.
@MainActor
@Observable
final class WatchLink: NSObject, WCSessionDelegate {
    private(set) var reachable = false
    private(set) var queued = 0
    private(set) var synced = 0
    private(set) var syncedBytes = 0
    /// Snippets handed to the queue so far. Sent with "finished" so the phone knows how many to wait for.
    private(set) var enqueuedTotal = 0

    /// Seconds of the recording processed so far; sent with each message so the phone can show the funnel.
    var recordedSoFar = 0.0

    /// Called when the phone asks the watch to start the replay (the demo driver does this; it is the same
    /// as tapping Start day).
    var onRemoteStart: ((Int) -> Void)?

    /// Called when the phone asks the watch to run quick-ask preset N (the demo driver does this).
    var onRemoteQuickAsk: ((Int) -> Void)?

    /// Called when the phone asks the watch to ask recorded question N by voice (the demo driver does this).
    var onRemoteVoiceAsk: ((Int) -> Void)?

    /// A promise the phone just heard the wearer make, shown as "Got it" until they keep it or it times out.
    struct CaughtPromise: Identifiable, Equatable {
        let id: String
        let text: String
        let due: String
    }
    var caught: CaughtPromise?

    /// The answer to a question that began "Hey Echo", shown until the wearer dismisses it.
    struct WakeReply: Identifiable, Equatable {
        let id = UUID()
        let question: String
        let text: String
        let source: WatchAnswer.Source
    }
    var wakeReply: WakeReply?
    let wakeSpeaker = Speaker()
    private var caughtGeneration = 0

    private struct Pending {
        let encoded: Data
        let index: Int
    }

    private var queue: [Pending] = []
    private var draining = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: Public

    func enqueue(_ meta: ChunkMeta, samples: [Int16]) {
        // Broadband noise compresses poorly, so fall back to a lower bitrate before giving up.
        var encoded: Data?
        for bitRate in [20_000, 12_000] {
            guard let audio = AudioCodec.encodeAAC(samples: samples, sampleRate: meta.sampleRate, bitRate: bitRate),
                  let entry = ChunkBundle.encodeEntry(.init(meta: meta, audio: audio)) else { continue }
            if entry.count + ChunkBundle.headerSize <= Wire.maxMessage { encoded = entry; break }
        }
        guard let encoded else {
            Log.link.error("chunk \(meta.index) could not be encoded under the message limit, dropped")
            return
        }
        queue.append(Pending(encoded: encoded, index: meta.index))
        enqueuedTotal += 1
        queued = queue.count
        Task { await drain() }
    }

    func resetCounters() {
        queue.removeAll()
        queued = 0
        synced = 0
        syncedBytes = 0
        enqueuedTotal = 0
    }

    /// Tells the phone the recording started or finished. The phone files what follows under the day this names, so "started" is
    /// retried until the phone answers (it may have only just opened); "finished" gets a few tries.
    func sendSession(state: String, recorded: Double, total: Double, count: Int = 0, dayOffset: Int = 0, live: Bool = false) async {
        let attempts = state == "started" ? 40 : 4
        for _ in 0..<attempts {
            for _ in 0..<20 where !WCSession.default.isReachable { try? await Task.sleep(for: .milliseconds(250)) }
            if (try? await message([
                Wire.typeKey: Wire.session, Wire.stateKey: state,
                Wire.recordedKey: recorded, Wire.totalKey: total, Wire.countKey: count, Wire.dayOffsetKey: dayOffset, Wire.liveKey: live,
            ])) != nil { return }
            try? await Task.sleep(for: .milliseconds(750))
        }
    }

    // MARK: Draining

    private func drain() async {
        guard !draining else { return }
        draining = true
        defer { draining = false }
        while !queue.isEmpty {
            var batch: [Pending] = []
            var size = ChunkBundle.headerSize
            for item in queue {
                if !batch.isEmpty && size + item.encoded.count > Wire.maxMessage { break }
                batch.append(item)
                size += item.encoded.count
            }
            if await send(batch) {
                queue.removeFirst(batch.count)
                synced += batch.count
                syncedBytes += size
                queued = queue.count
            } else {
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func send(_ batch: [Pending]) async -> Bool {
        guard WCSession.default.isReachable else { return false }
        let t0 = Date()
        let data = ChunkBundle.bundle(encodedEntries: batch.map(\.encoded), recorded: recordedSoFar)
        do {
            let reply = try await messageData(data)
            Log.link.info("sent \(batch.count) chunks (\(data.count) bytes) in \(Date().timeIntervalSince(t0), format: .fixed(precision: 2))s")
            return reply.first == 1
        } catch {
            Log.link.error("send failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Asks the phone a question and waits for its short answer. Gives up (nil) if the phone isn't reachable, the
    /// send fails, or nothing comes back within `timeout` (a live Muse answer takes about 7 s).
    nonisolated func ask(_ question: String, via: AskVia = .watch, timeout: TimeInterval = 40) async -> WatchAnswer? {
        let reply = await request([Wire.typeKey: Wire.ask, Wire.questionKey: question, Wire.viaKey: via.rawValue], timeout: timeout)
        return reply.flatMap { WatchAnswer(dictionary: $0) }
    }

    /// Sends a recorded question to the phone to be understood (on the phone, on-device). The audio is never kept.
    nonisolated func transcribe(_ clip: QuestionClip, timeout: TimeInterval = 25) async -> VoiceReply {
        VoiceReply(dictionary: await request([Wire.typeKey: Wire.transcribe, Wire.audioKey: clip.audio], timeout: timeout))
    }

    /// Asks the phone for a reminder about the promise shown. True if it was set.
    nonisolated func keep(promise id: String, timeout: TimeInterval = 10) async -> Bool {
        guard let reply = await request([Wire.typeKey: Wire.keepPromise, Wire.idKey: id], timeout: timeout) else { return false }
        return reply[Wire.okKey] as? Bool == true
    }

    func dismissCaught() { caught = nil }

    /// Asks the phone to forget the last `minutes` of what was heard. Returns how many moments it forgot (nil if it can't be reached).
    nonisolated func forget(minutes: Int, timeout: TimeInterval = 15) async -> Int? {
        guard let reply = await request([Wire.typeKey: Wire.forget, Wire.minutesKey: minutes], timeout: timeout),
              reply[Wire.okKey] as? Bool == true else { return nil }
        return reply[Wire.countKey] as? Int ?? 0
    }

    /// The phone's recent questions and answers (nil if it can't be reached).
    nonisolated func history(timeout: TimeInterval = 10) async -> [HistoryItem]? {
        guard let reply = await request([Wire.typeKey: Wire.history], timeout: timeout), reply[Wire.okKey] as? Bool == true,
              let items = reply[Wire.itemsKey] as? [[String: Any]] else { return nil }
        return items.compactMap { HistoryItem(dictionary: $0) }
    }

    /// One request with a reply, racing the reply, an error and a timeout. Nil if the phone isn't reachable or doesn't answer.
    private nonisolated func request(_ payload: [String: Any], timeout: TimeInterval) async -> [String: Any]? {
        guard WCSession.default.isReachable else { return nil }
        nonisolated(unsafe) let payload = payload
        return await withCheckedContinuation { (continuation: CheckedContinuation<[String: Any]?, Never>) in
            let once = Once()
            WCSession.default.sendMessage(payload, replyHandler: { reply in
                nonisolated(unsafe) let reply = reply
                if once.first() { continuation.resume(returning: reply) }
            }, errorHandler: { _ in
                if once.first() { continuation.resume(returning: nil) }
            })
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if once.first() { continuation.resume(returning: nil) }
            }
        }
    }

    private nonisolated func message(_ payload: [String: Any]) async throws -> [String: Any] {
        try await withCheckedThrowingContinuation { cont in
            WCSession.default.sendMessage(payload, replyHandler: { cont.resume(returning: $0) },
                                          errorHandler: { cont.resume(throwing: $0) })
        }
    }

    private nonisolated func messageData(_ data: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            WCSession.default.sendMessageData(data, replyHandler: { cont.resume(returning: $0) },
                                              errorHandler: { cont.resume(throwing: $0) })
        }
    }

    // MARK: WCSessionDelegate

    /// The phone's settings that the watch acts on (announce recording).
    nonisolated private func apply(context: [String: Any]) {
        if let announce = context[Wire.announceKey] as? Bool { UserDefaults.standard.set(announce, forKey: "echo.announce") }
        // The complication reads its promises from the App Group; the phone sends them here because the two devices don't share one.
        if let data = context[Wire.widgetKey] as? Data, let snapshot = WidgetSnapshot.decode(data) {
            snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(context: applicationContext)
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        apply(context: session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            Log.link.info("activated state=\(state.rawValue) reachable=\(reachable)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        switch message[Wire.typeKey] as? String {
        case Wire.demoStart:
            let offset = message[Wire.dayOffsetKey] as? Int ?? 0
            Task { @MainActor in self.onRemoteStart?(offset) }
        case Wire.demoQuickAsk:
            let index = message[Wire.presetKey] as? Int ?? 0
            Task { @MainActor in self.onRemoteQuickAsk?(index) }
        case Wire.promiseCaught:
            guard let id = message[Wire.idKey] as? String, let text = message[Wire.textKey] as? String else { return }
            let due = message[Wire.dueKey] as? String ?? ""
            Task { @MainActor in
                self.caught = CaughtPromise(id: id, text: text, due: due)
                self.caughtGeneration += 1
                let mine = self.caughtGeneration
                WKInterfaceDevice.current().play(.notification)
                try? await Task.sleep(for: .seconds(9))
                if self.caughtGeneration == mine { self.caught = nil }   // it was neither kept nor dismissed
            }
        case Wire.wakeAnswer:
            handleWake(message)
        case Wire.demoVoiceAsk:
            let index = message[Wire.presetKey] as? Int ?? 1
            Task { @MainActor in self.onRemoteVoiceAsk?(index) }
        default: break
        }
    }

    /// Answers that were waiting while the watch was away arrive here.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo[Wire.typeKey] as? String == Wire.wakeAnswer { handleWake(userInfo) }
    }

    nonisolated private func handleWake(_ message: [String: Any]) {
        guard let text = message[Wire.textKey] as? String else { return }
        let question = message[Wire.questionKey] as? String ?? ""
        let source = (message[Wire.sourceKey] as? String).flatMap(WatchAnswer.Source.init) ?? .none
        let speak = message[Wire.speakKey] as? Bool ?? false
        Task { @MainActor in
            let reply = WakeReply(question: question, text: text, source: source)
            self.wakeReply = reply
            WKInterfaceDevice.current().play(.notification)
            if speak { self.wakeSpeaker.speak(text) }
            try? await Task.sleep(for: .seconds(15))
            if self.wakeReply == reply { self.wakeReply = nil }   // left alone: it goes away by itself
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            Log.link.info("reachability -> \(reachable)")
            if reachable { await self.drain() }
        }
    }
}
