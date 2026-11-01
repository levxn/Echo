import Foundation
import Observation

/// The questions asked so far, newest first, kept in the phone's database. Wiped by Forget my day, a new watch replay
/// and Clear history, and never exported.
@MainActor
@Observable
final class AskHistoryModel {
    /// Older entries are dropped beyond this many.
    static let capacity = 200

    private(set) var items: [AskRecord] = []
    private let store: ChunkStore

    init(store: ChunkStore) { self.store = store }

    func reload() async { items = await store.history(limit: Self.capacity) }

    /// Adds a record (newest first) and saves it. Awaiting means it is on disk when this returns.
    func record(_ record: AskRecord) async {
        items.removeAll { $0.id == record.id }
        items.insert(record, at: 0)
        if items.count > Self.capacity { items.removeLast(items.count - Self.capacity) }
        await store.upsertHistory(record)
    }

    func delete(id: String) async {
        items.removeAll { $0.id == id }
        await store.deleteHistory(id: id)
    }

    func clear() async {
        items = []
        await store.clearHistory()
    }

    /// The last few distinct questions, newest first, in the short form the watch shows. Asking the same thing again shows
    /// only its latest answer there; the phone's own history keeps every time.
    func recentForWatch(limit: Int = 8) -> [HistoryItem] {
        var seen = Set<String>()
        var out: [HistoryItem] = []
        for record in items {
            guard seen.insert(record.question.lowercased()).inserted else { continue }
            out.append(record.item)
            if out.count == limit { break }
        }
        return out
    }

    func record(id: String) -> AskRecord? { items.first { $0.id == id } }
}
