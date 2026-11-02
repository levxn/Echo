import Foundation
import SQLite3
import Testing
@testable import Echo

private var utc: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: 0)!
    c.firstWeekday = 2   // weeks start on Monday
    return c
}

/// Monday 2 November 2026, noon.
private let monday = utc.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!

private func chunk(_ id: String, day: String, at wall: Double, _ text: String, index: Int = 0, status: ChunkStatus = .stored) -> ChunkRecord {
    ChunkRecord(id: id, index: index, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: status, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day)
}

struct DayIDTests {
    @Test func idsAreCalendarDatesAndOffsetsCountBackwards() {
        #expect(DayID.today(now: monday, calendar: utc) == "2026-11-02")
        #expect(DayID.id(offset: -1, from: monday, calendar: utc) == "2026-11-01")
        #expect(DayID.id(offset: -7, from: monday, calendar: utc) == "2026-10-26")
        #expect(DayID.id(offset: 30, from: monday, calendar: utc) == "2026-12-02")
        #expect(DayID.date(of: "2026-10-26", calendar: utc) == utc.date(from: DateComponents(year: 2026, month: 10, day: 26)))
        #expect(DayID.date(of: "nonsense", calendar: utc) == nil && DayID.date(of: "", calendar: utc) == nil)
    }

    @Test func labelsSayHowLongAgo() {
        func short(_ id: String) -> String { DayID.shortLabel(id, now: monday, calendar: utc) }
        func long(_ id: String) -> String { DayID.longLabel(id, now: monday, calendar: utc) }
        #expect(short("2026-11-02") == "Today" && short("") == "Today" && short("2026-11-01") == "Yesterday")
        #expect(short("2026-10-29") == "Thu", "within the last week it is the weekday")
        #expect(short("2026-10-10").contains("Oct"))
        #expect(long("2026-10-26") == "A week ago" && long("2026-11-01") == "Yesterday" && long("2026-11-02") == "Today")
        #expect(DayID.daysAgo("2026-10-26", now: monday, calendar: utc) == 7 && DayID.daysAgo("", now: monday, calendar: utc) == nil)
    }

    @Test func aMomentsStampCarriesTheDayOnlyWhenItIsNotToday() {
        let today = chunk("a", day: DayID.today(now: monday, calendar: utc), at: 45_000, "x")
        let old = chunk("b", day: "2026-10-26", at: 45_000, "x")
        let legacy = chunk("c", day: "", at: 45_000, "x")
        #expect(today.stamp(now: monday) == today.wallLabel && legacy.stamp(now: monday) == legacy.wallLabel)
        #expect(old.stamp(now: monday).hasSuffix(old.wallLabel) && old.stamp(now: monday) != old.wallLabel)
    }
}

struct DayScopeTests {
    private func scope(_ q: String) -> DayScope? { DayScope.parse(q, now: monday, calendar: utc)?.scope }

    @Test func questionsNameTheDaysTheyAreAbout() {
        #expect(scope("What did Brennan say yesterday?") == DayScope(from: "2026-11-01", to: "2026-11-01", label: "yesterday"))
        #expect(scope("What did I promise today?") == DayScope(from: "2026-11-02", to: "2026-11-02", label: "today"))
        #expect(scope("anything a week ago") == DayScope(from: "2026-10-26", to: "2026-10-26", label: "a week ago"))
        #expect(scope("what happened 3 days ago") == DayScope(from: "2026-10-30", to: "2026-10-30", label: "3 days ago"))
        #expect(scope("what happened two days ago")?.from == "2026-10-31")
        #expect(scope("What did the landlord say last week?") == DayScope(from: "2026-10-26", to: "2026-11-01", label: "last week"))
        #expect(scope("and this week?") == DayScope(from: "2026-11-02", to: "2026-11-02", label: "this week"))
        #expect(scope("the rent last month") == DayScope(from: "2026-10-01", to: "2026-10-31", label: "last month"))
        #expect(scope("what did she say last Friday") == DayScope(from: "2026-10-30", to: "2026-10-30", label: "last friday"))
        #expect(scope("what did she say last Monday")?.from == "2026-10-26", "last Monday on a Monday is a week ago")
    }

    @Test func questionsThatNameNoDayHaveNoScopeAndBareWeekdaysAreNotAnchors() {
        for q in ["When is the plumber coming?", "Summarize my day", "send it by Wednesday", "what did we decide on Friday", "next week"] {
            #expect(scope(q) == nil, "\(q)")
        }
    }

    @Test func theScopePhraseIsTakenOutOfTheWordsSearchedFor() {
        let parsed = QueryParser.parse("What did Brennan say about the lease last week?", now: monday, calendar: utc)
        #expect(parsed.dayScope?.label == "last week")
        #expect(!parsed.contentTokens.contains("week") && !parsed.contentTokens.contains("last") && parsed.contentTokens.contains("lease"))
        #expect(QueryParser.parse("When is the plumber coming?", now: monday, calendar: utc).dayScope == nil)
    }

    @Test func aScopeContainsItsDaysAndMomentsFromBeforeDaysExisted() {
        let s = DayScope(from: "2026-10-26", to: "2026-11-01", label: "last week")
        #expect(s.contains("2026-10-26") && s.contains("2026-11-01") && s.contains("") && !s.contains("2026-11-02") && !s.contains("2026-10-25"))
        #expect(!s.isSingleDay && DayScope(from: "a", to: "a", label: "").isSingleDay)
    }
}

struct DayStoreTests {
    private func store() throws -> (ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-days-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ChunkStore(directory: dir), dir)
    }

    @Test func aStoreFromBeforeDaysExistedKeepsItsMomentsAndCallsThemToday() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-old-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var db: OpaquePointer?
        #expect(sqlite3_open(dir.appending(path: "echo.sqlite").path, &db) == SQLITE_OK)
        sqlite3_exec(db, """
        CREATE TABLE chunk (id TEXT PRIMARY KEY, idx INTEGER, wall_start REAL, file_offset REAL, duration REAL, peak_db REAL, mean_db REAL,
          audio_file TEXT, status TEXT, speech_conf REAL, confirmed_seconds REAL, transcript TEXT, embedding BLOB);
        INSERT INTO chunk VALUES ('old', 0, 100, 0, 4, -10, -20, 'old.m4a', 'stored', 1, 4, 'the old plumber line', NULL);
        CREATE TABLE day_digest (id INTEGER PRIMARY KEY, ts REAL, json TEXT, model TEXT, is_stub INTEGER);
        INSERT INTO day_digest VALUES (1, 0, '{"day_summary":"old"}', 'm', 0);
        """, nil, nil, nil)
        sqlite3_close(db)

        let store = ChunkStore(directory: dir)
        let rows = await store.all()
        #expect(rows.map(\.id) == ["old"] && rows[0].dayId == DayID.today(), "it was captured today, as far as anyone knows")
        let digest = await store.loadDigest()?.json
        #expect(digest?.contains("old") == true, "its digest is today's")
    }

    @Test func aDayCanBeReplacedWithoutTouchingTheOthers() async throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(chunk("a1", day: "2026-10-26", at: 100, "last week one"))
        await store.upsert(chunk("a2", day: "2026-10-26", at: 200, "last week two", index: 1))
        await store.upsert(chunk("b1", day: "2026-11-02", at: 100, "today one"))
        await store.upsert(chunk("legacy", day: "", at: 300, "from before days"))
        let thatDay = await store.all(day: "2026-10-26").map(\.id)
        #expect(thatDay == ["legacy", "a1", "a2"], "old moments count as any day's, and come first")
        let removed = await store.deleteDay("2026-10-26")
        #expect(Set(removed) == ["a1", "a2", "legacy"])
        let rest = await store.all().map(\.id)
        #expect(rest == ["b1"], "today's day is untouched")
    }

    @Test func readingBackOrdersByDayThenPosition() async throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(chunk("t1", day: "2026-11-02", at: 50, "t1", index: 0))
        await store.upsert(chunk("w2", day: "2026-10-26", at: 90, "w2", index: 1))
        await store.upsert(chunk("w1", day: "2026-10-26", at: 40, "w1", index: 0))
        let order = await store.all().map(\.id)
        #expect(order == ["w1", "w2", "t1"])
    }

    @Test func purgingForgetsOnlyDaysBeforeTheCutoffAndTheirDigests() async throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(chunk("old", day: "2026-09-01", at: 10, "very old"))
        await store.upsert(chunk("mid", day: "2026-10-26", at: 10, "last week"))
        await store.upsert(chunk("new", day: "2026-11-02", at: 10, "today"))
        await store.upsert(chunk("legacy", day: "", at: 10, "unknown day"))
        await store.saveDigest(json: "{}", model: "m", isStub: false, day: "2026-09-01")
        await store.saveDigest(json: "{}", model: "m", isStub: false, day: "2026-11-02")
        let purged = await store.purge(before: "2026-10-26")
        let left = Set(await store.all().map(\.id))
        #expect(purged == 1 && left == ["mid", "new", "legacy"], "an unknown day is never purged")
        let kept = await store.digests().map(\.day)
        #expect(kept == ["2026-11-02"])
    }

    @Test func digestsAreKeptPerDayAndReplacedOnRepeat() async throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.saveDigest(json: "one", model: "m", isStub: false, day: "2026-10-26")
        await store.saveDigest(json: "two", model: "m", isStub: true, day: "2026-11-02")
        await store.saveDigest(json: "three", model: "m", isStub: false, day: "2026-11-02")
        let first = await store.loadDigest(day: "2026-10-26")?.json
        #expect(first == "one")
        let latest = await store.loadDigest(day: "2026-11-02")?.json
        let count = await store.digests().count
        #expect(latest == "three" && count == 2)
        let none = await store.loadDigest(day: "2000-01-01")
        #expect(none == nil)
    }

    @Test func deletingMomentsAlsoDropsHistoryThatCitedThem() async throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(chunk("c1", day: "2026-10-26", at: 10, "one"))
        await store.upsert(chunk("c2", day: "2026-11-02", at: 10, "two"))
        let citing = AskRecord(question: "q1", shortAnswer: "a", source: .local, via: .typed,
                               detail: AskDetail(kind: .local, headline: "a", sourceChunkIDs: ["c1"]))
        let other = AskRecord(question: "q2", shortAnswer: "a", source: .local, via: .typed,
                              detail: AskDetail(kind: .local, headline: "a", sourceChunkIDs: ["c2"]))
        await store.upsertHistory(citing)
        await store.upsertHistory(other)
        await store.deleteDay("2026-10-26")
        let remaining = await store.history().map(\.question)
        #expect(remaining == ["q2"])
    }

    @Test func daysListsWhatIsStoredNewestFirst() async throws {
        let (store, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(chunk("a", day: "2026-10-26", at: 1, "x"))
        await store.upsert(chunk("b", day: "2026-11-02", at: 1, "x"))
        await store.upsert(chunk("c", day: "2026-11-02", at: 2, "x", index: 1))
        await store.upsert(chunk("d", day: "2026-11-02", at: 3, "x", index: 2, status: .dropped))
        let days = await store.days()
        #expect(days.map(\.day) == ["2026-11-02", "2026-10-26"] && days.map(\.count) == [2, 1])
    }
}

@MainActor
struct DaySessionTests {
    private func model() throws -> (PipelineModel, ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-sess-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        let m = PipelineModel(store: store, defaults: UserDefaults(suiteName: "echo-sess-\(UUID().uuidString)")!)
        m.now = { monday }
        return (m, store, dir)
    }

    @Test func aNewSessionReplacesOnlyItsOwnDay() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        await m.sessionStarted(total: 100, dayId: "2026-10-26")
        m.put(chunk("w1", day: m.activeDayId, at: 10, "last week"))
        await m.sessionStarted(total: 100)   // today
        #expect(m.activeDayId == "2026-11-02")
        m.put(chunk("t1", day: m.activeDayId, at: 10, "today"))
        try await Task.sleep(for: .milliseconds(100))
        let kept = Set(await store.all().map(\.id))
        #expect(m.chunks.map(\.id) == ["w1", "t1"] && kept == ["w1", "t1"])
        await m.sessionStarted(total: 100)   // replaying today starts today clean, last week stays
        let after = Set(await store.all().map(\.id))
        #expect(m.chunks.map(\.id) == ["w1"])
        #expect(after == ["w1"])
    }

    @Test func todayAndTheSessionAreDifferentViewsOfTheMemory() async throws {
        let (m, _, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        await m.sessionStarted(total: 100)
        m.put(chunk("t1", day: "2026-11-02", at: 10, "today"))
        await m.sessionStarted(total: 100, dayId: "2026-10-26")
        m.put(chunk("w1", day: "2026-10-26", at: 10, "last week"))
        #expect(m.todayChunks.map(\.id) == ["t1"], "Today shows today")
        #expect(m.sessionChunks.map(\.id) == ["w1"], "the funnel is about what the watch is sending now")
        #expect(m.arrivedCount == 1 && m.storedCount == 2, "a question can be about either day")
        #expect(m.chunks(on: "2026-10-26").map(\.id) == ["w1"])
    }

    @Test func theActiveDaySurvivesARelaunch() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-sess2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "echo-sess2-\(UUID().uuidString)")!
        let first = PipelineModel(store: ChunkStore(directory: dir), defaults: defaults)
        await first.sessionStarted(total: 10, dayId: "2026-10-26")
        let second = PipelineModel(store: ChunkStore(directory: dir), defaults: defaults)
        #expect(second.activeDayId == "2026-10-26", "chunks that arrive after a relaunch still go to the right day")
    }
}

struct DayRetrievalTests {
    private func store(_ chunks: [ChunkRecord]) async throws -> (ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-ret-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        for c in chunks {
            await store.upsert(c)
            await store.index(id: c.id, normalizedText: TextNormalizer.normalized(c.transcript ?? ""), embedding: Embedder.vector(for: c.transcript ?? ""))
        }
        return (store, dir)
    }

    private let lastWeek = "2026-10-26", yesterday = "2026-11-01", today = "2026-11-02"

    @Test func aQuestionThatNamesADayOnlyLooksAtThatDay() async throws {
        let (s, dir) = try await store([
            chunk("w", day: lastWeek, at: 100, "The rent goes up three percent from January."),
            chunk("t", day: today, at: 100, "The rent goes up four percent from January.", index: 1),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let retriever = Retriever(store: s, now: monday)
        let past = await retriever.search("What was said about the rent a week ago?")
        #expect(past.hits.map(\.chunk.id) == ["w"] && past.dayScope?.label == "a week ago")
        let now = await retriever.search("What was said about the rent today?")
        #expect(now.hits.map(\.chunk.id) == ["t"])
    }

    @Test func withNoDayNamedTheNewerMemoryWinsACloseCall() async throws {
        let same = "The plumber is coming on Friday at ten."
        let (s, dir) = try await store([
            chunk("old", day: lastWeek, at: 100, same),
            chunk("new", day: today, at: 100, same, index: 1),
        ])
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await Retriever(store: s, now: monday).search("When is the plumber coming?")
        #expect(outcome.hits.first?.chunk.id == "new", "identical matches: the latest one first")
        #expect(outcome.hits.map(\.chunk.id).contains("old"), "the older memory is still found")
    }

    @Test func aSingleDayBehavesExactlyAsBefore() async throws {
        let (s, dir) = try await store([chunk("a", day: today, at: 100, "The plumber is coming on Friday.")])
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = await Retriever(store: s, now: monday).search("When is the plumber coming?")
        #expect(outcome.hits.map(\.chunk.id) == ["a"] && outcome.dayScope == nil)
    }
}

struct RetentionAndResurfacingTests {
    @Test func theCutoffIsTheFirstDayThatIsKeptAndForeverNeverExpires() {
        #expect(Retention.cutoff(days: 7, now: monday, calendar: utc) == "2026-10-26")
        #expect(Retention.cutoff(days: 30, now: monday, calendar: utc) == "2026-10-03")
        #expect(Retention.cutoff(days: 0, now: monday, calendar: utc) == nil)
        #expect(Retention.title(days: 0) == "Forever" && Retention.title(days: 90) == "90 days" && Retention.title(days: 12) == "12 days")
        #expect(Retention.options.map(\.days) == [7, 30, 90, 0])
    }

    @MainActor @Test func oldDaysAreForgottenWhenTheSettingSaysSoAndNewerOnesStay() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-ret2-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let defaults = UserDefaults(suiteName: "echo-ret2-\(UUID().uuidString)")!
        let model = PipelineModel(store: ChunkStore(directory: dir), defaults: defaults)
        model.now = { monday }
        for (id, day) in [("a", "2026-09-01"), ("b", "2026-10-26"), ("c", "2026-11-02"), ("d", "")] { model.put(chunk(id, day: day, at: 10, id)) }
        defaults.set(7, forKey: Retention.key)
        await model.purgeExpired()
        #expect(model.chunks.map(\.id) == ["d", "b", "c"], "the one from before days existed stays")
        defaults.set(0, forKey: Retention.key)
        await model.purgeExpired()
        #expect(model.chunks.count == 3, "forever keeps everything")
    }

    @Test func thePastHasASuggestionOnlyOnTheDatesThatHaveAMemory() {
        let weekAgo = chunk("w", day: "2026-10-26", at: 100, "I will send the contract by Friday and book the kickoff call.")
        let other = chunk("o", day: "2026-10-20", at: 100, "An unrelated day nobody asks about.")
        let found = Resurfacing.suggestions(from: [weekAgo, other], now: monday, calendar: utc)
        #expect(found.map(\.title) == ["A week ago today"])
        #expect(found.first?.question == "What happened a week ago?" && found.first?.moments == 1 && found.first?.conversations == 1)
        let gist = found.first?.gist ?? ""
        #expect(!gist.isEmpty)
        #expect(Resurfacing.suggestions(from: [], now: monday, calendar: utc).isEmpty)
    }

    @Test func theQuestionAResurfacedCardAsksIsUnderstoodAsThatDay() {
        for span in Resurfacing.spans {
            let scope = DayScope.parse("What happened \(span.phrase)?", now: monday, calendar: utc)?.scope
            #expect(scope?.isSingleDay == true && scope?.from == DayID.id(offset: -span.days, from: monday, calendar: utc), "\(span.phrase)")
        }
        #expect(DayScope.parse("Summarize my past week", now: monday, calendar: utc)?.scope.from == "2026-10-26")
        #expect(DayScope.parse("Summarize my past week", now: monday, calendar: utc)?.scope.to == "2026-11-02")
    }
}
