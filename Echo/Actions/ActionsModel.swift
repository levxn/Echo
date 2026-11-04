import Foundation
import Observation

/// Which actions the list shows.
nonisolated enum ActionFilter: String, CaseIterable, Identifiable, Sendable {
    case all, calendar, messages, todos, waiting
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .calendar: "Calendar"
        case .messages: "Messages"
        case .todos: "To-dos"
        case .waiting: "Waiting on"
        }
    }

    func includes(_ kind: ActionKind) -> Bool {
        switch self {
        case .all: true
        case .calendar: kind == .calendar
        case .messages: kind == .email || kind == .message
        case .todos: kind == .todo || kind == .shopping || kind == .call
        case .waiting: kind == .waiting
        }
    }
}

/// The Actions page's data: what people said they would do (found on the phone, and optionally by Muse), what the person has decided about
/// each, and the drafts they have edited. Decisions and edits are kept on the phone, and go when the moments they came from go.
@MainActor
@Observable
final class ActionsModel {
    enum Section: String, CaseIterable, Identifiable {
        case overdue, today, thisWeek, later, noDate
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overdue: "Overdue"
            case .today: "Today"
            case .thisWeek: "This week"
            case .later: "Later"
            case .noDate: "No date"
            }
        }
    }

    struct Group: Identifiable, Equatable {
        let section: Section
        let items: [ActionItem]
        var id: String { section.rawValue }
    }

    /// Everything found, as it was found, oldest first.
    private var found: [ActionItem] = []
    private(set) var states: [String: ActionState] = [:]
    /// Everything found, with the person's edits applied.
    var items: [ActionItem] { found.map { apply(states[$0.id]?.edits ?? ActionEdits(), to: $0) } }
    private let store: ChunkStore
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current
    /// Whose name goes at the bottom of an email draft (set by the last refresh).
    private(set) var userName = ""

    init(store: ChunkStore) { self.store = store }

    // MARK: Finding

    /// Works out the actions from the moments (off the main thread), adds what Muse found earlier, and applies what the person has done.
    func refresh(chunks: [ChunkRecord], userName: String, myVoice: String?, voiceNames: [String: String]) async {
        let moment = now(), cal = calendar
        self.userName = userName.isEmpty ? self.userName : userName
        let rules = await Task.detached(priority: .utility) {
            ActionExtractor.extract(from: chunks, userName: userName, myVoice: myVoice, voiceName: { voiceNames[$0] }, now: moment, calendar: cal)
        }.value
        let live = Set(chunks.map(\.id))
        var all = rules
        for fromMuse in await store.museActions() where live.contains(fromMuse.chunkID) && !rules.contains(where: { ActionExtractor.isSameThing($0, fromMuse) }) { all.append(fromMuse) }
        let stored = await store.actionStates()
        states = Dictionary(stored.filter { s in all.contains { $0.id == s.id } }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        found = all.sorted { ($0.dayId, $0.wallStart, $0.id) < ($1.dayId, $1.wallStart, $1.id) }
    }

    /// Adds actions found by Muse (kept until the moments they came from are forgotten).
    func addFromMuse(_ found: [ActionItem], model: String, chunks: [ChunkRecord], userName: String, myVoice: String?, voiceNames: [String: String]) async {
        await store.saveMuseActions(found, model: model)
        await refresh(chunks: chunks, userName: userName, myVoice: myVoice, voiceNames: voiceNames)
    }

    private func apply(_ edits: ActionEdits, to item: ActionItem) -> ActionItem {
        var a = item
        if let t = edits.title, !t.trimmingCharacters(in: .whitespaces).isEmpty { a.title = t }
        if edits.noDate { a.due = nil; a.dueText = nil } else if let d = edits.due { a.due = d }
        if let m = edits.durationMinutes { a.durationMinutes = m }
        if let allDay = edits.allDay { a.allDay = allDay }
        if let list = edits.items { a.items = list }
        return a
    }

    // MARK: What the person sees

    func status(of id: String) -> ActionStatus { states[id]?.status ?? .new }
    func state(of id: String) -> ActionState? { states[id] }
    func edits(for id: String) -> ActionEdits { states[id]?.edits ?? ActionEdits() }

    private func isPending(_ item: ActionItem) -> Bool {
        let moment = now()
        if item.isStale(now: moment) { return false }
        switch status(of: item.id) {
        case .new: return true
        case .snoozed: return (states[item.id]?.snoozedUntil ?? .distantPast) <= moment
        case .done, .dismissed: return false
        }
    }

    var pending: [ActionItem] { items.filter(isPending) }
    /// What has been dealt with, newest first.
    var done: [ActionItem] { items.filter { status(of: $0.id) == .done }.sorted { (states[$0.id]?.changed ?? .distantPast) > (states[$1.id]?.changed ?? .distantPast) } }
    /// The number on the tab.
    var pendingCount: Int { pending.count }

    func count(_ filter: ActionFilter) -> Int { pending.filter { filter.includes($0.kind) }.count }

    func section(of item: ActionItem) -> Section {
        guard let due = item.due else { return .noDate }
        let moment = now()
        if due < moment && !item.allDay { return .overdue }
        let today = calendar.startOfDay(for: moment)
        let day = calendar.startOfDay(for: due)
        let ahead = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        if ahead < 0 { return .overdue }
        return ahead == 0 ? .today : (ahead <= 7 ? .thisWeek : .later)
    }

    /// The pending actions, grouped by when they are due, soonest first (those without a date: the most recent first).
    func groups(_ filter: ActionFilter = .all) -> [Group] {
        let shown = pending.filter { filter.includes($0.kind) }
        return Section.allCases.compactMap { section in
            let inSection = shown.filter { self.section(of: $0) == section }
            guard !inSection.isEmpty else { return nil }
            let sorted = section == .noDate ? inSection.sorted { ($0.dayId, $0.wallStart) > ($1.dayId, $1.wallStart) }
                                            : inSection.sorted { ($0.due ?? .distantFuture, $0.wallStart) < ($1.due ?? .distantFuture, $1.wallStart) }
            return Group(section: section, items: sorted)
        }
    }

    // MARK: What the person does

    private func update(_ id: String, _ change: (inout ActionState) -> Void) async {
        guard let item = found.first(where: { $0.id == id }) else { return }
        var s = states[id] ?? ActionState(id: id, chunkID: item.chunkID, status: .new, changed: now())
        change(&s)
        s.changed = now()
        states[id] = s
        await store.saveActionState(s)
    }

    func markDone(_ id: String, via: String? = nil) async { await update(id) { $0.status = .done; $0.handedOffVia = via; $0.snoozedUntil = nil } }
    func dismiss(_ id: String) async { await update(id) { $0.status = .dismissed; $0.snoozedUntil = nil } }
    func snooze(_ id: String, until: Date) async { await update(id) { $0.status = .snoozed; $0.snoozedUntil = until } }
    /// Back onto the list (undo, or "move back" from Done).
    func restore(_ id: String) async { await update(id) { $0.status = .new; $0.snoozedUntil = nil; $0.handedOffVia = nil } }

    /// Keeps the person's edits (the draft they were writing, a changed time). An unedited action leaves no row behind.
    func saveEdits(_ id: String, _ edits: ActionEdits) async {
        await update(id) { $0.edits = edits }
        if let state = states[id], state.edits.isEmpty, state.status == .new {
            states[id] = nil
            await store.deleteActionState(id: id)
        }
    }

    /// Forget my day.
    func reset() { found = []; states = [:] }
}
