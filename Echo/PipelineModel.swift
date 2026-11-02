import Foundation
import Observation

/// Observable state behind the phone UI: the chunk list, the funnel, and the replay session.
@MainActor
@Observable
final class PipelineModel {
    enum Session { case waiting, running, finished }

    /// Every moment from every day, oldest day first.
    private(set) var chunks: [ChunkRecord] = []
    private(set) var session: Session = .waiting
    /// The day the watch is capturing (or last captured). New moments are stamped with it.
    private(set) var activeDayId: String
    private(set) var recordedSeconds = 0.0
    private(set) var totalSeconds = 0.0
    private(set) var watchReachable = false
    /// How many snippets the watch said it sent in all (0 until it says, or if it is an older watch).
    private(set) var expectedChunks = 0

    let store: ChunkStore
    private let defaults: UserDefaults
    /// Replaced in tests.
    var now: () -> Date = { Date() }

    /// `store` and `defaults` are injectable so tests can use a temporary folder and their own settings; the app uses its own.
    init(store: ChunkStore = ChunkStore(), defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        activeDayId = defaults.string(forKey: Key.day) ?? DayID.today()
    }

    /// The replay's totals survive app restarts, so the funnel still reads correctly afterwards.
    private enum Key {
        static let recorded = "echo.recordedSeconds"
        static let total = "echo.totalSeconds"
        static let finished = "echo.sessionFinished"
        static let expected = "echo.expectedChunks"
        static let day = "echo.activeDay"
    }

    // MARK: Which day

    /// The moments of the day being captured: what the funnel and the Moments tab are about.
    var sessionChunks: [ChunkRecord] { chunks.filter { $0.isOn(activeDayId) } }
    /// Today's moments: what Today, its summary, commitments and people show.
    var todayChunks: [ChunkRecord] { let today = DayID.today(now: now()); return chunks.filter { $0.isOn(today) } }
    func chunks(on day: String) -> [ChunkRecord] { chunks.filter { $0.isOn(day) } }

    // MARK: Funnel (recorded -> watch kept -> phone confirmed)

    var watchKeptSeconds: Double { sessionChunks.reduce(0) { $0 + $1.duration } }
    var phoneConfirmedSeconds: Double { sessionChunks.reduce(0) { $0 + $1.confirmedSeconds } }
    var arrivedCount: Int { sessionChunks.count }
    var checkedCount: Int { sessionChunks.filter { $0.status != .received }.count }
    var transcribedCount: Int { sessionChunks.filter { $0.status == .asr || $0.status == .stored }.count }
    /// Moments kept from every day (a question can be about any of them).
    var storedCount: Int { chunks.filter { $0.status == .stored }.count }
    var droppedCount: Int { sessionChunks.filter { $0.status == .dropped }.count }
    /// Chunks still moving through the pipeline.
    var pendingCount: Int { chunks.filter { $0.status == .received || $0.status == .vad }.count }
    /// Snippets the watch says it sent that have not arrived yet.
    var missingCount: Int { max(0, expectedChunks - arrivedCount) }
    /// True once the watch has finished, all of what it sent has arrived, and all of it has been processed. The watch's
    /// "finished" message can come before its last snippets are delivered, so that alone doesn't mean the day is here.
    var isSettled: Bool { session == .finished && pendingCount == 0 && missingCount == 0 }
    var sessionFraction: Double { totalSeconds > 0 ? min(1, recordedSeconds / totalSeconds) : 0 }
    var savedFraction: Double {
        recordedSeconds > 0 ? max(0, 1 - phoneConfirmedSeconds / recordedSeconds) : 0
    }

    func load() async {
        chunks = await store.all()
        let d = defaults
        recordedSeconds = d.double(forKey: Key.recorded)
        totalSeconds = d.double(forKey: Key.total)
        expectedChunks = d.integer(forKey: Key.expected)
        if !chunks.isEmpty { session = d.bool(forKey: Key.finished) ? .finished : (recordedSeconds > 0 ? .running : .waiting) }
    }

    /// Writes the current session state. The watch's "finished" message can arrive while its last chunks are
    /// still draining, so later bundles must not overwrite it.
    private func persistSession() {
        let d = defaults
        d.set(recordedSeconds, forKey: Key.recorded)
        d.set(totalSeconds, forKey: Key.total)
        d.set(session == .finished, forKey: Key.finished)
        d.set(expectedChunks, forKey: Key.expected)
        d.set(activeDayId, forKey: Key.day)
    }

    func setReachable(_ value: Bool) { watchReachable = value }

    /// A new capture session for `dayId` (today unless the watch says otherwise). That day starts clean; other days stay.
    func sessionStarted(total: Double, dayId: String? = nil) async {
        let day = dayId ?? DayID.today(now: now())
        await store.deleteDay(day)
        chunks.removeAll { $0.isOn(day) }
        activeDayId = day
        await purgeExpired()
        recordedSeconds = 0
        expectedChunks = 0
        totalSeconds = total
        session = .running
        persistSession()
    }

    /// Forgets days older than the retention setting (30 days unless the person chose otherwise).
    func purgeExpired() async {
        let days = defaults.object(forKey: Retention.key) as? Int ?? Retention.defaultDays
        guard let cutoff = Retention.cutoff(days: days, now: now()) else { return }
        await store.purge(before: cutoff)
        chunks.removeAll { !$0.dayId.isEmpty && $0.dayId < cutoff }
    }

    func sessionFinished(recorded: Double, expectedChunks: Int = 0) {
        recordedSeconds = recorded
        self.expectedChunks = expectedChunks
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
        expectedChunks = 0
        session = .waiting
        persistSession()
    }

    /// Inserts or replaces a record and persists it.
    func put(_ record: ChunkRecord) {
        if let i = chunks.firstIndex(where: { $0.id == record.id }) { chunks[i] = record } else {
            chunks.append(record)
            chunks.sort { ($0.dayId, $0.index) < ($1.dayId, $1.index) }
        }
        Task { await store.upsert(record) }
    }

    func record(id: String) -> ChunkRecord? { chunks.first { $0.id == id } }

    /// Deletes one moment from the day: its transcript, audio file and search entry. Search reads the store on every
    /// query and Today, Commitments and the feed are derived from `chunks`, so it disappears from all of them.
    func remove(id: String) async {
        chunks.removeAll { $0.id == id }
        await store.delete(id: id)
    }
}
