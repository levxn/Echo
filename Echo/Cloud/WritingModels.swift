import Foundation
import Observation

/// "Draft the message": Muse writes the message that keeps a promise, from only that moment and the line before it. Goes
/// through the review gate and the ledger like every other request.
@MainActor
@Observable
final class DraftModel {
    struct Ready {
        let draft: MessageDraft
        let model: String
        let isStub: Bool
    }

    enum State {
        case idle
        case working(TierTwoPlan)
        case ready(Ready)
        case failed(String)
        case cloudOff
    }

    private(set) var state: State = .idle
    private let caller: CloudCaller
    private let ledger: LedgerModel
    private let modelID: String

    init(ledger: LedgerModel, client: any MuseClient, model: String = MuseClientFactory.model) {
        self.ledger = ledger
        self.caller = CloudCaller(client: client, ledger: ledger)
        self.modelID = model
    }

    var isStub: Bool { caller.client.isStub }

    /// `instruction` replaces the usual "keep this promise" request (for a follow-up to someone, or a message about an action).
    func generate(for promise: Promise, tone: DraftTone, channel: DraftChannel, chunks: [ChunkRecord], instruction: String? = nil) async {
        guard ledger.cloudEnabled else { state = .cloudOff; return }
        let plan = TierTwoPlanner.draftPlan(promise: promise, chunks: chunks, tone: tone, channel: channel, model: modelID, maskNames: ledger.maskNames, instruction: instruction)
        guard plan.canCall else { state = .failed("That moment is no longer on this phone."); return }
        let query = "Draft a \(channel == .email ? "email" : "text message") for: “\(promise.sentence)”"
        if ledger.reviewBeforeSend, !isStub {
            let approved = await ledger.gate.confirm(plan: plan, query: query, kind: .draft)
            if !approved {
                var entry = LedgerEntry(query: query, tier: .cloud, reason: "You chose not to send this.")
                entry.kind = .draft
                entry.snippets = plan.snippets
                ledger.record(entry)
                state = .idle
                return
            }
        }
        state = .working(plan)
        switch await caller.perform(plan: plan, query: query, kind: .draft, reason: "You asked Muse to draft a message for a promise.") {
        case .success(let response):
            guard let parsed = MessageDraft.parse(response.content) else { state = .failed("Muse's message couldn't be read. Try again."); return }
            state = .ready(Ready(draft: parsed.restoredOnPhone(plan.masking), model: response.model, isStub: response.isStub))
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }

    func reset() { state = .idle }
}

/// A private journal entry for a day, written by Muse when the person asks, and kept on this phone.
@MainActor
@Observable
final class JournalModel {
    struct Ready: Equatable {
        let day: String
        let entry: JournalEntry
        let model: String
        let isStub: Bool
    }

    enum State {
        case idle
        case working(TierTwoPlan)
        case ready(Ready)
        case failed(String)
        case cloudOff
    }

    private(set) var state: State = .idle
    /// Entries from other days, newest first.
    private(set) var earlier: [Ready] = []
    private let store: ChunkStore
    private let caller: CloudCaller
    private let ledger: LedgerModel
    private let modelID: String

    init(store: ChunkStore, ledger: LedgerModel, client: any MuseClient, model: String = MuseClientFactory.model) {
        self.store = store
        self.ledger = ledger
        self.caller = CloudCaller(client: client, ledger: ledger)
        self.modelID = model
    }

    var isStub: Bool { caller.client.isStub }

    func load(today: String = DayID.today()) async {
        let all = await store.journals().compactMap { row -> Ready? in
            JournalEntry.parse(row.json).map { Ready(day: row.day, entry: $0, model: row.model, isStub: row.isStub) }
        }
        earlier = all.filter { $0.day != today }
        if let mine = all.first(where: { $0.day == today }) { state = .ready(mine) } else if case .ready = state { state = .idle }
    }

    func generate(chunks: [ChunkRecord], day: String = DayID.today()) async {
        guard ledger.cloudEnabled else { state = .cloudOff; return }
        let plan = TierTwoPlanner.journalPlan(chunks: chunks, day: day, model: modelID, maskNames: ledger.maskNames)
        guard plan.canCall else { return }
        let query = "Write my journal entry for today"
        if ledger.reviewBeforeSend, !isStub {
            let approved = await ledger.gate.confirm(plan: plan, query: query, kind: .journal)
            if !approved {
                var entry = LedgerEntry(query: query, tier: .cloud, reason: "You chose not to send this.")
                entry.kind = .journal
                entry.snippets = plan.snippets
                ledger.record(entry)
                state = .idle
                return
            }
        }
        state = .working(plan)
        switch await caller.perform(plan: plan, query: query, kind: .journal, reason: "You asked Muse to write your journal entry.") {
        case .success(let response):
            guard let parsed = JournalEntry.parse(response.content) else { state = .failed("Muse's entry couldn't be read. Try again."); return }
            let entry = parsed.restored(plan.masking)
            // Saved with names already back in place, so a reload needs no mapping.
            let json = (try? String(data: JSONEncoder().encode(entry), encoding: .utf8)) ?? response.content
            await store.saveJournal(json: json, model: response.model, isStub: response.isStub, day: day)
            state = .ready(Ready(day: day, entry: entry, model: response.model, isStub: response.isStub))
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }

    /// The day was forgotten.
    func reset() { state = .idle; earlier = [] }
}

/// A gentle evening nudge to write the journal, when the person wants one. It says nothing about the day.
nonisolated enum JournalReminder {
    static let key = "echo.journalReminder"
    static let notificationID = "echo.journal.evening"
    static let hour = 21

    /// The next 9 pm.
    static func fireDate(now: Date, calendar: Calendar = .current) -> Date? {
        guard let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { return nil }
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
    }
}
