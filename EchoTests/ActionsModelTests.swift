import Foundation
import Testing
@testable import Echo

@MainActor
struct ActionsModelTests {
    private let calendarUTC: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    /// Monday 2 November 2026, 10:00.
    private var monday: Date { calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 10))! }

    private func chunk(_ id: String, _ text: String, at wall: Double, day: String = "2026-11-02", speaker: String = "") -> ChunkRecord {
        ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a", status: .stored,
                    speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day, speakerId: speaker)
    }

    private let day = [
        ("a", "Right I will send you the API specification by Wednesday noon that's a promise", 36_000.0),
        ("b", "I have booked a plumber to come on Friday at 10 in the morning", 36_040),
        ("c", "I will transfer the rent tomorrow first thing", 36_080),
        ("d", "Remember to buy a birthday card", 36_120),
        ("e", "I will pay the invoice tomorrow morning", 36_160),
    ]

    private func rig() async throws -> (model: ActionsModel, store: ChunkStore, chunks: [ChunkRecord], dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-actions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        // the last line was said a week ago, so "tomorrow morning" has already gone by
        let chunks = day.map { chunk($0.0, $0.1, at: $0.2, day: $0.0 == "e" ? "2026-10-26" : "2026-11-02") }
        for c in chunks { await store.upsert(c) }
        let model = ActionsModel(store: store)
        model.now = { self.monday }
        model.calendar = calendarUTC
        await model.refresh(chunks: chunks, userName: "Levin", myVoice: nil, voiceNames: [:])
        return (model, store, chunks, dir)
    }

    @Test func theListIsFoundGroupedByWhenItIsDueAndCounted() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let m = r.model
        #expect(m.pendingCount == m.items.count && m.pendingCount >= 5, "\(m.items.map(\.title))")
        let groups = m.groups()
        #expect(groups.map(\.section) == [.overdue, .today, .thisWeek, .noDate].filter { s in groups.contains { $0.section == s } }, "in order of when: \(groups.map(\.section))")
        let tomorrow = try #require(m.items.first { $0.title.hasPrefix("Transfer") })
        #expect(m.section(of: tomorrow) == .thisWeek)
        let spec = try #require(m.items.first { $0.title.hasPrefix("Send the API") })
        #expect(m.section(of: spec) == .thisWeek)
        let overdue = try #require(m.items.first { $0.title.hasPrefix("Pay the invoice") })
        #expect(m.section(of: overdue) == .overdue, "said last Monday for 'tomorrow morning': overdue, not hidden")
        #expect(m.section(of: try #require(m.items.first { $0.title.hasPrefix("Buy a birthday card") })) == .noDate)
        #expect(m.count(.calendar) == 1 && m.count(.waiting) == 0 && m.count(.all) == m.pendingCount)
    }

    @Test func doneAndDismissedLeaveTheListAndSurviveARestart() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let a = try #require(r.model.items.first { $0.id == "a#a0" }), b = try #require(r.model.items.first { $0.id == "b#a0" })
        let before = r.model.pendingCount
        await r.model.markDone(a.id, via: "Mail")
        await r.model.dismiss(b.id)
        #expect(r.model.pendingCount == before - 2 && r.model.done.map(\.id) == [a.id])
        #expect(r.model.state(of: a.id)?.handedOffVia == "Mail" && r.model.status(of: b.id) == .dismissed)
        // a new model over the same store, as after the app restarts
        let again = ActionsModel(store: r.store); again.now = { self.monday }; again.calendar = calendarUTC
        await again.refresh(chunks: r.chunks, userName: "Levin", myVoice: nil, voiceNames: [:])
        #expect(again.pendingCount == before - 2 && again.status(of: a.id) == .done && again.state(of: a.id)?.handedOffVia == "Mail")
    }

    @Test func undoPutsItBackAndSnoozeHidesItUntilItsTime() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let id = "c#a0"
        let before = r.model.pendingCount
        await r.model.markDone(id)
        await r.model.restore(id)
        #expect(r.model.pendingCount == before && r.model.status(of: id) == .new && r.model.state(of: id)?.handedOffVia == nil)
        await r.model.snooze(id, until: monday.addingTimeInterval(3 * 3600))
        #expect(r.model.pendingCount == before - 1, "snoozed: not waiting for review")
        r.model.now = { self.monday.addingTimeInterval(4 * 3600) }
        #expect(r.model.pendingCount == before, "and back when the time has come")
    }

    @Test func editsAreKeptAndShownAndAnUneditedActionLeavesNoRow() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let id = "a#a0"
        let when = calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9))!
        var e = ActionEdits(); e.title = "Send Ravi the spec"; e.due = when; e.body = "Hi Ravi, here it is."; e.bodyEditedByPerson = true; e.channel = .whatsapp
        await r.model.saveEdits(id, e)
        #expect(r.model.items.first { $0.id == id }?.title == "Send Ravi the spec" && r.model.items.first { $0.id == id }?.due == when)
        #expect(r.model.edits(for: id).body == "Hi Ravi, here it is." && r.model.edits(for: id).channel == .whatsapp)
        let again = ActionsModel(store: r.store); again.now = { self.monday }; again.calendar = calendarUTC
        await again.refresh(chunks: r.chunks, userName: "Levin", myVoice: nil, voiceNames: [:])
        #expect(again.edits(for: id).body == "Hi Ravi, here it is." && again.items.first { $0.id == id }?.title == "Send Ravi the spec", "the draft is still there")
        // clearing the edits brings back what was found, and leaves nothing stored
        await again.saveEdits(id, ActionEdits())
        #expect(again.items.first { $0.id == id }?.title == "Send the API specification")
        let stored = await r.store.actionStates()
        #expect(!stored.contains { $0.id == id })
        // clearing the date
        var none = ActionEdits(); none.noDate = true
        await again.saveEdits(id, none)
        #expect(again.items.first { $0.id == id }?.due == nil)
    }

    @Test func aCalendarEventThatHasPassedIsNotOnTheList() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let before = r.model.pendingCount
        r.model.now = { self.calendarUTC.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 9))! }   // the plumber came last Friday
        #expect(r.model.pendingCount == before - 1 && !r.model.pending.contains { $0.kind == .calendar })
    }

    @Test func forgettingMomentsRemovesTheirActionsAndTheirDrafts() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        var e = ActionEdits(); e.body = "draft"
        await r.model.saveEdits("a#a0", e)
        await r.model.markDone("b#a0")
        #expect(await r.store.actionStates().count == 2)
        _ = await r.store.deleteChunks(ids: ["a", "b"])
        #expect(await r.store.actionStates().isEmpty, "decisions and drafts about forgotten moments go with them")
        let remaining = await r.store.all()
        await r.model.refresh(chunks: remaining, userName: "Levin", myVoice: nil, voiceNames: [:])
        #expect(!r.model.items.contains { $0.chunkID == "a" || $0.chunkID == "b" })
        await r.store.reset()
        let stateAfterReset = await r.store.actionStates()
        let museAfterReset = await r.store.museActions()
        #expect(stateAfterReset.isEmpty && museAfterReset.isEmpty)
    }

    @Test func whatMuseFoundIsKeptDedupedAndForgottenWithItsMoment() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        let rulesCount = r.model.items.count
        var fresh = ActionItem(id: "d#m0", kind: .todo, title: "Ask Maya about the venue", quote: "Remember to buy a birthday card", chunkID: "d", dayId: "2026-11-02", wallStart: 36_120, timeLabel: "10:02")
        fresh.origin = .muse
        let echo = ActionItem(id: "a#m0", kind: .email, title: "Send the API specification to Ravi", quote: "", chunkID: "a", dayId: "2026-11-02", wallStart: 36_000, timeLabel: "10:00")
        await r.model.addFromMuse([fresh, echo], model: "muse", chunks: r.chunks, userName: "Levin", myVoice: nil, voiceNames: [:])
        #expect(r.model.items.contains { $0.id == "d#m0" } && r.model.items.count == rulesCount + 1, "something new from Muse is kept")
        #expect(!r.model.items.contains { $0.id == "a#m0" }, "the same email, already found by the rules, is not listed twice")
        let stored = await r.store.museActions()
        #expect(stored.count == 2)
        _ = await r.store.deleteChunks(ids: ["d", "a"])
        #expect(await r.store.museActions().isEmpty, "gone with the moments they came from")
    }

    @Test func resetEmptiesTheModel() async throws {
        let r = try await rig()
        defer { try? FileManager.default.removeItem(at: r.dir) }
        r.model.reset()
        #expect(r.model.items.isEmpty && r.model.pendingCount == 0 && r.model.groups().isEmpty)
    }
}
