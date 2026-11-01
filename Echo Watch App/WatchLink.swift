import Foundation
import Observation
import os
import WatchConnectivity

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
    var onRemoteStart: (() -> Void)?

    /// Called when the phone asks the watch to run quick-ask preset N (the demo driver does this).
    var onRemoteQuickAsk: ((Int) -> Void)?

    /// Called when the phone asks the watch to ask recorded question N by voice (the demo driver does this).
    var onRemoteVoiceAsk: ((Int) -> Void)?

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

    /// Best-effort notice that the replay started or finished.
    func sendSession(state: String, recorded: Double, total: Double, count: Int = 0) async {
        for _ in 0..<20 where !WCSession.default.isReachable { try? await Task.sleep(for: .milliseconds(250)) }
        _ = try? await message([
            Wire.typeKey: Wire.session, Wire.stateKey: state,
            Wire.recordedKey: recorded, Wire.totalKey: total, Wire.countKey: count,
        ])
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

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            Log.link.info("activated state=\(state.rawValue) reachable=\(reachable)")
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        switch message[Wire.typeKey] as? String {
        case Wire.demoStart:
            Task { @MainActor in self.onRemoteStart?() }
        case Wire.demoQuickAsk:
            let index = message[Wire.presetKey] as? Int ?? 0
            Task { @MainActor in self.onRemoteQuickAsk?(index) }
        case Wire.demoVoiceAsk:
            let index = message[Wire.presetKey] as? Int ?? 1
            Task { @MainActor in self.onRemoteVoiceAsk?(index) }
        default: break
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
