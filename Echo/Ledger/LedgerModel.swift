import Foundation
import Observation

/// The privacy ledger plus the cloud on/off switch.
@MainActor
@Observable
final class LedgerModel {
    private(set) var entries: [LedgerEntry] = []
    /// Whether the "How Echo works" sheet is showing. Lives here so the demo driver can open it.
    var showArchitecture = ProcessInfo.processInfo.arguments.contains("-architecture")
    private let store: ChunkStore
    private static let cloudKey = "echo.cloudEnabled"

    /// Kill switch: when off, no question ever leaves the phone.
    var cloudEnabled: Bool {
        didSet { UserDefaults.standard.set(cloudEnabled, forKey: Self.cloudKey) }
    }

    init(store: ChunkStore) {
        self.store = store
        cloudEnabled = UserDefaults.standard.object(forKey: Self.cloudKey) as? Bool ?? true
    }

    var totals: LedgerTotals { LedgerTotals(entries) }

    func reload() async { entries = await store.ledgerEntries() }

    /// Inserts or updates an entry, keeping the list newest-first.
    func record(_ entry: LedgerEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) { entries[i] = entry } else {
            entries.insert(entry, at: 0)
        }
        Task { await store.upsertLedger(entry) }
    }

    func clear() async {
        await store.clearLedger()
        entries = []
    }
}
