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
    private let defaults: UserDefaults
    private static let cloudKey = "echo.cloudEnabled"
    private static let reviewKey = "echo.reviewBeforeSend"
    private static let maskKey = "echo.maskNames"
    /// Off by default. Checked live against Muse Spark: no name reached the request and the restored answers read well,
    /// but a word the recognizer misheard as a name ("leave" heard as "Lee") is masked too, so Muse can no longer
    /// reconcile that slip and lists it as a person. Private by choice, not by default.
    static let maskNamesDefault = false

    /// When on, people's names are replaced with placeholders before text leaves the phone, and restored in the
    /// answer. Best effort: it can only mask names the on-device tagger finds.
    var maskNames: Bool {
        didSet { defaults.set(maskNames, forKey: Self.maskKey) }
    }

    /// Holds a cloud call until the user has seen and approved exactly what would be sent.
    let gate = ReviewGate()

    /// When on, every cloud request waits for the user's approval first.
    var reviewBeforeSend: Bool {
        didSet { defaults.set(reviewBeforeSend, forKey: Self.reviewKey) }
    }

    /// Kill switch: when off, no question ever leaves the phone.
    var cloudEnabled: Bool {
        didSet { defaults.set(cloudEnabled, forKey: Self.cloudKey) }
    }

    /// `defaults` is injectable so tests can run in parallel without sharing the user's real switches.
    init(store: ChunkStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        cloudEnabled = defaults.object(forKey: Self.cloudKey) as? Bool ?? true
        // Dev hook: `-review on|off` sets the preference (screenshots and the demo take).
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-review"), i + 1 < args.count, ["on", "off"].contains(args[i + 1]) {
            defaults.set(args[i + 1] == "on", forKey: Self.reviewKey)
        }
        reviewBeforeSend = defaults.object(forKey: Self.reviewKey) as? Bool ?? false
        // Dev hook: `-mask on|off`.
        if let i = args.firstIndex(of: "-mask"), i + 1 < args.count, ["on", "off"].contains(args[i + 1]) {
            defaults.set(args[i + 1] == "on", forKey: Self.maskKey)
        }
        maskNames = defaults.object(forKey: Self.maskKey) as? Bool ?? Self.maskNamesDefault
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
