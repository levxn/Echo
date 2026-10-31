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

    // MARK: Funnel (recorded -> watch kept -> phone confirmed)

    var watchKeptSeconds: Double { chunks.reduce(0) { $0 + $1.duration } }
    var phoneConfirmedSeconds: Double { chunks.reduce(0) { $0 + $1.confirmedSeconds } }
    var droppedCount: Int { chunks.filter { $0.status == .dropped }.count }
    var storedCount: Int { chunks.filter { $0.status == .stored }.count }
    var savedFraction: Double {
        recordedSeconds > 0 ? max(0, 1 - phoneConfirmedSeconds / recordedSeconds) : 0
    }

    func load() async { chunks = await store.all() }

    func setReachable(_ value: Bool) { watchReachable = value }

    func sessionStarted(total: Double) async {
        await store.reset()
        chunks = []
        recordedSeconds = 0
        totalSeconds = total
        session = .running
    }

    func sessionFinished(recorded: Double) {
        recordedSeconds = recorded
        session = .finished
    }

    func updateRecorded(_ seconds: Double) {
        recordedSeconds = max(recordedSeconds, seconds)
        if session == .waiting { session = .running }
    }

    func reset() async {
        await store.reset()
        chunks = []
        recordedSeconds = 0
        totalSeconds = 0
        session = .waiting
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
