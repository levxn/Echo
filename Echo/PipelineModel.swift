import Foundation
import Observation

/// Observable state behind the phone UI: the chunk list, the funnel, and the replay session.
@MainActor
@Observable
final class PipelineModel {
    enum Session { case waiting, running, finished }

    private(set) var chunks: [ChunkRecord] = []
    private(set) var session: Session = .waiting
    private(set) var recordedSeconds = 0.0
    private(set) var totalSeconds = 0.0
    private(set) var watchReachable = false

    let store = ChunkStore()

    /// The replay's totals survive app restarts, so the funnel still reads correctly afterwards.
    private enum Key {
        static let recorded = "echo.recordedSeconds"
        static let total = "echo.totalSeconds"
        static let finished = "echo.sessionFinished"
    }

    // MARK: Funnel (recorded -> watch kept -> phone confirmed)

    var watchKeptSeconds: Double { chunks.reduce(0) { $0 + $1.duration } }
    var phoneConfirmedSeconds: Double { chunks.reduce(0) { $0 + $1.confirmedSeconds } }
    var arrivedCount: Int { chunks.count }
    var checkedCount: Int { chunks.filter { $0.status != .received }.count }
    var transcribedCount: Int { chunks.filter { $0.status == .asr || $0.status == .stored }.count }
    var storedCount: Int { chunks.filter { $0.status == .stored }.count }
    var droppedCount: Int { chunks.filter { $0.status == .dropped }.count }
    /// Chunks still moving through the pipeline.
    var pendingCount: Int { chunks.filter { $0.status == .received || $0.status == .vad }.count }
    /// True once the watch has finished and everything it sent has been processed.
    var isSettled: Bool { session == .finished && pendingCount == 0 }
    var sessionFraction: Double { totalSeconds > 0 ? min(1, recordedSeconds / totalSeconds) : 0 }
    var savedFraction: Double {
        recordedSeconds > 0 ? max(0, 1 - phoneConfirmedSeconds / recordedSeconds) : 0
    }

    func load() async {
        chunks = await store.all()
        let d = UserDefaults.standard
        recordedSeconds = d.double(forKey: Key.recorded)
        totalSeconds = d.double(forKey: Key.total)
        if !chunks.isEmpty { session = d.bool(forKey: Key.finished) ? .finished : (recordedSeconds > 0 ? .running : .waiting) }
    }

    /// Writes the current session state. The watch's "finished" message can arrive while its last chunks are
    /// still draining, so later bundles must not overwrite it.
    private func persistSession() {
        let d = UserDefaults.standard
        d.set(recordedSeconds, forKey: Key.recorded)
        d.set(totalSeconds, forKey: Key.total)
        d.set(session == .finished, forKey: Key.finished)
    }

    func setReachable(_ value: Bool) { watchReachable = value }

    func sessionStarted(total: Double) async {
        await store.reset()
        chunks = []
        recordedSeconds = 0
        totalSeconds = total
        session = .running
        persistSession()
    }

    func sessionFinished(recorded: Double) {
        recordedSeconds = recorded
        session = .finished
        persistSession()
    }

    func updateRecorded(_ seconds: Double) {
        recordedSeconds = max(recordedSeconds, seconds)
        if session == .waiting { session = .running }
        persistSession()
    }

    func reset() async {
        await store.reset()
        chunks = []
        recordedSeconds = 0
        totalSeconds = 0
        session = .waiting
        persistSession()
    }

    /// Inserts or replaces a record and persists it.
    func put(_ record: ChunkRecord) {
        if let i = chunks.firstIndex(where: { $0.id == record.id }) { chunks[i] = record } else {
            chunks.append(record)
            chunks.sort { $0.index < $1.index }
        }
        Task { await store.upsert(record) }
    }

    func record(id: String) -> ChunkRecord? { chunks.first { $0.id == id } }
}
