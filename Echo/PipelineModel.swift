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
    /// When the watch last said or sent anything (a session starting, a bundle of audio).
    private(set) var lastWatchActivity: Date?
    /// The watch paused listening without ending the session.
    private(set) var watchPaused = false
    /// What the watch last said about its microphone (nil until it says). It tells the phone on every change, when it reconnects and
    /// every half minute, because "reachable" doesn't mean "listening" and a session can be left open.
    private(set) var watchListening: Bool?
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

    /// Whether the watch is listening right now. The watch says when it starts and stops, so if it never gets to say it stopped (the app was
    /// force-quit, the battery died) the phone would stay "listening" for ever: after three quiet minutes out of reach, it isn't.
    var isListening: Bool { _ = clock; return isListening(at: now()) }

    /// Bumped every few seconds by the app so that "the watch went quiet" shows up on screen even when nothing else changes.
    private(set) var clock = 0
    func tickClock() { clock &+= 1 }

    /// Listening was paused on the watch (the microphone is off) but the session isn't over.
    var isPaused: Bool { session == .running && watchPaused }

    func setPaused(_ paused: Bool) {
        watchPaused = paused
        watchListening = !paused
        lastWatchActivity = now()
    }

    /// The watch says whether its microphone is on.
    func setWatchListening(_ on: Bool) {
        watchListening = on
        if on { watchPaused = false }
        lastWatchActivity = now()
    }

    func isListening(at date: Date) -> Bool {
        guard session == .running, !watchPaused, watchListening != false else { return false }
        guard let last = lastWatchActivity else { return false }
        let quiet = date.timeIntervalSince(last)
        // The watch said it is listening: believe it while it is near, and for three minutes after it goes out of reach.
        if watchListening == true { return watchReachable || quiet < 180 }
        // It hasn't said (a session from an earlier run may never have been closed): only fresh signs of life count.
        return quiet < (watchReachable ? 60 : 180)
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

    func setReachable(_ value: Bool) {
        // Out of reach, what it last said is out of date; it says again as soon as it is back.
        if !value { watchListening = nil }
        watchReachable = value
    }

    /// A new capture session for `dayId` (today unless the watch says otherwise). That day starts clean; other days stay.
    /// A watch that listens live starts a session every time it resumes, and what it already heard today must stay (`keepExisting`).
    func sessionStarted(total: Double, dayId: String? = nil, keepExisting: Bool = false) async {
        let day = dayId ?? DayID.today(now: now())
        if !keepExisting {
            await store.deleteDay(day)
            chunks.removeAll { $0.isOn(day) }
        }
        activeDayId = day
        await purgeExpired()
        recordedSeconds = 0
        expectedChunks = 0
        totalSeconds = total
        session = .running
        watchPaused = false
        watchListening = true
        lastWatchActivity = now()
        persistSession()
    }

    /// Forgets days older than the retention setting (30 days unless the person chose otherwise).
    func purgeExpired() async {
        let days = defaults.object(forKey: Retention.key) as? Int ?? Retention.defaultDays
        guard let cutoff = Retention.cutoff(days: days, now: now()) else { return }
        await store.purge(before: cutoff)
        chunks.removeAll { !$0.dayId.isEmpty && $0.dayId < cutoff }
    }

    /// Forgets the last `minutes` of what was captured: the moments, their audio and search entries, the history that cited them
    /// and the day's summary. Returns the ids that were forgotten.
    @discardableResult
    func forgetLast(minutes: Int) async -> [String] {
        let doomed = ForgetWindow.chunks(in: chunks, minutes: minutes)
        guard !doomed.isEmpty else { return [] }
        let ids = doomed.map(\.id)
        await store.deleteChunks(ids: ids)
        for day in Set(doomed.map(\.dayId)) {
            let d = day.isEmpty ? DayID.today(now: now()) : day
            await store.deleteDigest(day: d)
            await store.deleteJournal(day: d)
        }
        chunks.removeAll { ids.contains($0.id) }
        return ids
    }

    func sessionFinished(recorded: Double, expectedChunks: Int = 0) {
        recordedSeconds = recorded
        self.expectedChunks = expectedChunks
        watchPaused = false
        watchListening = false
        session = .finished
        persistSession()
    }

    func updateRecorded(_ seconds: Double) {
        recordedSeconds = max(recordedSeconds, seconds)
        if session == .waiting { session = .running }
        lastWatchActivity = now()
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
