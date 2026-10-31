import Foundation
import Observation
import os
import WatchConnectivity

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

    /// Seconds of the recording processed so far; sent with each message so the phone can show the funnel.
    var recordedSoFar = 0.0

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
        queued = queue.count
        Task { await drain() }
    }

    func resetCounters() {
        queue.removeAll()
        queued = 0
        synced = 0
        syncedBytes = 0
    }

    /// Best-effort notice that the replay started or finished.
    func sendSession(state: String, recorded: Double, total: Double) async {
        for _ in 0..<20 where !WCSession.default.isReachable { try? await Task.sleep(for: .milliseconds(250)) }
        _ = try? await message([
            Wire.typeKey: Wire.session, Wire.stateKey: state,
            Wire.recordedKey: recorded, Wire.totalKey: total,
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

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.reachable = reachable
            Log.link.info("reachability -> \(reachable)")
            if reachable { await self.drain() }
        }
    }
}
