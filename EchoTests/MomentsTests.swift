import Foundation
import Testing
@testable import Echo

@MainActor
struct MomentsTests {
    // MARK: Status banner

    private func status(_ phase: CaptureStatus.Phase = .waiting, reachable: Bool = false, arrived: Int = 0, pending: Int = 0,
                        stored: Int = 0, ignored: Int = 0, conversations: Int = 0, kept: Double = 0, fraction: Double = 0,
                        expected: Int = 0) -> CaptureStatus {
        CaptureStatus.make(phase: phase, reachable: reachable, arrived: arrived, pending: pending, stored: stored, ignored: ignored,
                           conversations: conversations, keptSeconds: kept, fraction: fraction, expected: expected)
    }

    @Test func beforeAnythingHappensItSaysWhetherTheWatchIsThere() {
        let away = status(reachable: false)
        #expect(away.kind == .waitingForWatch && away.title == "Waiting for your watch" && away.progress == nil)
        let near = status(reachable: true)
        #expect(near.kind == .watchReady && near.detail.contains("big button"))
    }

    @Test func whileTheWatchListensItCountsMomentsAndShowsProgress() {
        let s = status(.running, reachable: true, arrived: 21, ignored: 3, fraction: 0.4)
        #expect(s.kind == .listening && s.title == "Listening")
        #expect(s.detail == "18 moments so far", "noise already ruled out is not counted")
        #expect(s.progress == 0.4)
    }

    @Test func afterTheWatchFinishesItShowsTheCatchUp() {
        let s = status(.finished, reachable: true, arrived: 56, pending: 14)
        #expect(s.kind == .catchingUp && s.detail == "Understanding 42 of 56")
        #expect(abs((s.progress ?? 0) - 0.75) < 0.0001)
    }

    @Test func ifTheWatchFinishedButSnippetsAreStillOnTheWayItIsNotCaughtUp() {
        let s = status(.finished, reachable: true, arrived: 12, pending: 0, stored: 12, conversations: 1, kept: 60, expected: 56)
        #expect(s.kind == .catchingUp && s.detail == "Understanding 12 of 56", "44 are still on the watch")
        #expect(abs((s.progress ?? 0) - 12.0 / 56.0) < 0.0001)
        #expect(status(.finished, arrived: 56, stored: 45, ignored: 11, conversations: 4, kept: 233, expected: 56).kind == .caughtUp)
        #expect(status(.finished, arrived: 56, stored: 45, ignored: 11, conversations: 4, kept: 233, expected: 0).kind == .caughtUp,
                "an older watch that sends no count behaves as before")
    }

    @Test func whenSettledItSummarizesTheDayInPlainWords() {
        let s = status(.finished, reachable: true, arrived: 56, stored: 45, ignored: 11, conversations: 4, kept: 233)
        #expect(s.kind == .caughtUp && s.title == "Caught up")
        #expect(s.detail == "45 moments from 4 conversations · 3 min 53 s kept")
        #expect(s.footnote == "Everything stays on this phone." && s.progress == nil)
        #expect(status(.finished, arrived: 1, stored: 1, conversations: 1, kept: 5).detail == "1 moment from 1 conversation · 5 s kept")
    }

    @Test func nothingTheBannerSaysUsesInternalJargon() {
        let all = [status(), status(reachable: true), status(.running, arrived: 5, fraction: 0.1),
                   status(.finished, arrived: 5, pending: 2), status(.finished, arrived: 5, stored: 5, conversations: 1, kept: 30)]
        for s in all {
            let text = [s.title, s.detail, s.footnote ?? ""].joined(separator: " ").lowercased()
            for word in ["chunk", "stage", "vad", "asr", "fts", "pipeline", "received", "dropped"] {
                #expect(!text.contains(word), "“\(word)” should not appear in: \(text)")
            }
        }
    }

    @Test func durationsReadNaturally() {
        #expect(Format.minutesSeconds(233) == "3 min 53 s" && Format.minutesSeconds(240) == "4 min")
        #expect(Format.minutesSeconds(45) == "45 s" && Format.minutesSeconds(0) == "0 s" && Format.minutesSeconds(-3) == "0 s")
    }

    // MARK: The feed

    private func record(_ c: ChunkRecord, _ status: ChunkStatus, transcript: String? = nil) -> ChunkRecord {
        var copy = c
        copy.status = status
        if status != .stored { copy.transcript = transcript }
        return copy
    }

    @Test func theFeedGroupsTheFixtureIntoItsFourConversations() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let layout = MomentsLayout.make(from: h.chunks)
        #expect(layout.groups.count == 4)
        #expect(layout.groups.map(\.count).reduce(0, +) == h.chunks.count, "every understood moment is listed once")
        #expect(layout.groups.map(\.startLabel) == layout.groups.map(\.startLabel).sorted(), "in time order")
        #expect(layout.working.isEmpty && layout.ignored == 0 && layout.failed == 0)
        #expect(Set(layout.groups.map(\.id)).count == 4, "group ids are distinct")
        #expect(layout.groups.allSatisfy { $0.title.hasSuffix("conversation") })
    }

    @Test func momentsStillBeingUnderstoodAreSeparateAndNoiseIsOnlyCounted() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        var chunks = h.chunks
        chunks[0] = record(chunks[0], .received)                         // not yet checked
        chunks[1] = record(chunks[1], .vad)                              // checked, not transcribed
        chunks[2] = record(chunks[2], .asr, transcript: "hello there")   // transcribed, not yet stored
        chunks[3] = record(chunks[3], .dropped)
        chunks[4] = record(chunks[4], .failed)
        let layout = MomentsLayout.make(from: chunks)
        #expect(layout.working.count == 3)
        #expect(layout.working.filter(\.isWorking).count == 2, "received and checked moments have no text yet")
        #expect(layout.working.first { !$0.isWorking }?.text == "hello there")
        #expect(layout.working.allSatisfy { $0.inFlight }, "none of them can be played or deleted yet")
        #expect(layout.groups.flatMap(\.items).allSatisfy { !$0.inFlight })
        #expect(layout.ignored == 1 && layout.failed == 1)
        #expect(layout.groups.map(\.count).reduce(0, +) == chunks.count - 5, "none of those five is in a conversation")
    }

    @Test func groupsStayOpenOnlyWhileTheDayIsArriving() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let layout = MomentsLayout.make(from: h.chunks)
        let newest = try #require(layout.groups.last).id
        #expect(MomentsLayout.openGroups(layout, settled: false, mode: nil) == [newest], "live: the newest conversation is open")
        #expect(MomentsLayout.openGroups(layout, settled: true, mode: nil).isEmpty, "settled: the page is short")
        #expect(MomentsLayout.openGroups(layout, settled: true, mode: "all").count == 4)
        #expect(MomentsLayout.openGroups(layout, settled: true, mode: "latest") == [newest])
        #expect(MomentsLayout.openGroups(layout, settled: false, mode: "none").isEmpty)
        #expect(MomentsLayout.openGroups(MomentsLayout(groups: [], working: [], ignored: 0, failed: 0), settled: false, mode: nil).isEmpty)
    }

    // MARK: The ribbon

    @Test func barHeightsStayInRangeAndTrackMomentLength() {
        let bars = Ribbon.bars(durations: [2, 4, 8, 6])
        #expect(bars.count == 4 && bars.allSatisfy { $0 >= Ribbon.minHeight && $0 <= 1 })
        #expect(bars[2] == 1 && bars[0] < bars[1] && bars[1] < bars[3])
        #expect(Ribbon.bars(durations: []).isEmpty)
        #expect(Ribbon.bars(durations: [0, 0]) == [0.5, 0.5], "no lengths known: neutral bars")
    }

    @Test func aLongConversationIsSampledDownToAReadableNumberOfBars() {
        let bars = Ribbon.bars(durations: Array(repeating: 5, count: 200))
        #expect(bars.count == Ribbon.maxBars)
    }

    @Test func blockWidthsAddUpAndNoBlockVanishes() {
        let shares = Ribbon.shares(counts: [10, 12, 12, 11])
        #expect(abs(shares.reduce(0, +) - 1) < 0.0001 && shares.allSatisfy { $0 >= Ribbon.minShare * 0.9 })
        let skewed = Ribbon.shares(counts: [1, 40, 40, 40])
        #expect(abs(skewed.reduce(0, +) - 1) < 0.0001)
        #expect(skewed[0] > 0.08, "a one-moment conversation is still wide enough to tap")
        #expect(Ribbon.shares(counts: [7]) == [1] && Ribbon.shares(counts: []).isEmpty)
    }

    // MARK: Behind the scenes

    @Test func behindTheScenesTellsTheFixtureStoryInPlainSentences() {
        let lines = BehindTheScenes.lines(arrived: 56, stored: 45, ignored: 11, failed: 0, recorded: 375, kept: 288, confirmed: 233)
        #expect(lines.count == 4)
        #expect(lines[0] == "56 short snippets arrived from the watch.")
        #expect(lines[1] == "45 were speech and are kept; 11 were noise and ignored.")
        #expect(lines[2] == "The watch kept 4 min 48 s of the 6 min 15 s it heard, and the phone confirmed 3 min 53 s as speech.")
        #expect(lines[3] == "All of it was checked and transcribed on this phone.")
    }

    @Test func behindTheScenesHandlesSingularsAndFailures() {
        let lines = BehindTheScenes.lines(arrived: 1, stored: 1, ignored: 0, failed: 2, recorded: 0, kept: 0, confirmed: 0)
        #expect(lines[0] == "1 short snippet arrived from the watch.")
        #expect(lines[1] == "1 was speech and is kept; 0 were noise and ignored. 2 snippets couldn't be processed.")
        #expect(lines.count == 3, "no recording totals, so no duration sentence")
    }
}

@MainActor
struct DeleteMomentTests {
    @Test func deletingAMomentRemovesItsRowSearchEntryAndAudio() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let target = try #require(h.chunks.first { ($0.transcript ?? "").lowercased().contains("plumber") })
        try await h.store.write(audio: Data("fake audio".utf8), named: target.audioFile)
        let file = await h.store.url(for: target.audioFile)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect((await h.store.ftsSearch(tokens: ["plumber"], limit: 20)).contains { $0.id == target.id })

        await h.store.delete(id: target.id)

        #expect(!(await h.store.all()).contains { $0.id == target.id }, "the row is gone")
        #expect(!(await h.store.ftsSearch(tokens: ["plumber"], limit: 20)).contains { $0.id == target.id }, "so is its search entry")
        #expect(!(await h.store.embeddings()).keys.contains(target.id), "and its embedding")
        #expect(!FileManager.default.fileExists(atPath: file.path), "and its audio file")
        #expect((await h.store.all()).count == h.chunks.count - 1, "nothing else was touched")
    }

    @Test func deletingAnUnknownIdChangesNothing() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        await h.store.delete(id: "no-such-moment")
        #expect((await h.store.all()).count == h.chunks.count)
    }

    @Test func theModelDropsItEverywhereTheDayIsDerivedFrom() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = PipelineModel(store: h.store)
        await model.load()
        #expect(model.chunks.count == h.chunks.count)
        let target = try #require(model.chunks.first { ($0.transcript ?? "").contains("I will send you the API specification") })

        await model.remove(id: target.id)

        #expect(model.record(id: target.id) == nil && model.chunks.count == h.chunks.count - 1)
        #expect(!MomentsLayout.make(from: model.chunks).groups.flatMap(\.items).contains { $0.id == target.id }, "not in the feed")
        #expect(!EpisodeBuilder.build(from: model.chunks).flatMap(\.chunks).contains { $0.id == target.id }, "not in Today's day")
        #expect(!PromiseExtractor.extract(from: model.chunks).contains { $0.chunkID == target.id }, "not in Commitments")
        let outcome = await h.retriever.search("API specification Wednesday noon")
        #expect(!outcome.hits.contains { $0.chunk.id == target.id }, "Ask can no longer find it")
        await model.load()
        #expect(model.record(id: target.id) == nil, "and it stays gone after a reload")
    }
}

struct TabNamingTests {
    @Test func theOldPipelineNameStillOpensMoments() {
        #expect(RootTab.from(argument: "pipeline") == .moments, "older scripts and docs say pipeline")
        #expect(RootTab.from(argument: "moments") == .moments)
        #expect(RootTab.from(argument: "today") == .day && RootTab.from(argument: "day") == .day, "older scripts say today")
        #expect(RootTab.from(argument: "ask") == .ask && RootTab.from(argument: "actions") == .actions)
        #expect(RootTab.from(argument: "ledger") == .you && RootTab.from(argument: "privacy") == .you && RootTab.from(argument: "profile") == .you && RootTab.from(argument: "you") == .you)
        #expect(RootTab.from(argument: "nonsense") == nil)
    }
}

@MainActor
struct SettlingTests {
    @Test func theDayIsNotSettledUntilEverythingTheWatchSentHasArrived() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = PipelineModel(store: h.store, defaults: UserDefaults(suiteName: "echo-settle-\(UUID().uuidString)")!)
        await model.sessionStarted(total: 375)
        for chunk in h.chunks.prefix(10) { model.put(chunk) }
        // The watch says it is finished, and that it sent all 45 — but only 10 have arrived.
        model.sessionFinished(recorded: 375, expectedChunks: h.chunks.count)
        #expect(model.pendingCount == 0 && model.session == .finished)
        #expect(model.missingCount == h.chunks.count - 10)
        #expect(!model.isSettled, "most of the day is still on its way")

        for chunk in h.chunks.dropFirst(10) { model.put(chunk) }
        #expect(model.missingCount == 0 && model.isSettled)
    }

    @Test func aWatchThatSendsNoCountSettlesAsBefore() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = PipelineModel(store: h.store, defaults: UserDefaults(suiteName: "echo-settle-\(UUID().uuidString)")!)
        await model.sessionStarted(total: 375)
        for chunk in h.chunks.prefix(10) { model.put(chunk) }
        model.sessionFinished(recorded: 375)   // no expected count
        #expect(model.expectedChunks == 0 && model.missingCount == 0 && model.isSettled)
    }

    @Test func aNewSessionForgetsTheOldExpectation() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let model = PipelineModel(store: h.store, defaults: UserDefaults(suiteName: "echo-settle-\(UUID().uuidString)")!)
        model.sessionFinished(recorded: 1, expectedChunks: 99)
        #expect(model.expectedChunks == 99)
        await model.sessionStarted(total: 375)
        #expect(model.expectedChunks == 0)
        model.sessionFinished(recorded: 1, expectedChunks: 5)
        await model.reset()
        #expect(model.expectedChunks == 0 && model.missingCount == 0)
    }

    @Test func theCountSurvivesARelaunch() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let defaults = UserDefaults(suiteName: "echo-settle-\(UUID().uuidString)")!
        let model = PipelineModel(store: h.store, defaults: defaults)
        await model.sessionStarted(total: 375)
        for chunk in h.chunks.prefix(5) { model.put(chunk) }
        model.sessionFinished(recorded: 375, expectedChunks: 56)
        try await Task.sleep(for: .milliseconds(200))   // put() saves in the background
        let reopened = PipelineModel(store: h.store, defaults: defaults)
        await reopened.load()
        #expect(reopened.expectedChunks == 56 && reopened.session == .finished && !reopened.isSettled)
    }
}
