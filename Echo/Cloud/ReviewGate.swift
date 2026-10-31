import Foundation
import Observation

/// "Review before sending": holds a cloud call until the user has seen exactly what would be sent and approved
/// it. One gate is shared by Ask and the digest (through `LedgerModel`), so both are covered.
@MainActor
@Observable
final class ReviewGate {
    struct Pending: Identifiable {
        let id = UUID()
        let query: String
        let kind: LedgerEntry.Kind
        let plan: TierTwoPlan
    }

    private(set) var pending: Pending?
    private var continuation: CheckedContinuation<Bool, Never>?

    /// Suspends until the user approves (true) or declines (false). A second request while one is waiting
    /// declines the first, so a continuation is never left hanging or resumed twice.
    func confirm(plan: TierTwoPlan, query: String, kind: LedgerEntry.Kind) async -> Bool {
        resolve(false)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            pending = Pending(query: query, kind: kind, plan: plan)
        }
    }

    func approve() { resolve(true) }
    /// Also what dismissing the sheet means.
    func cancel() { resolve(false) }

    private func resolve(_ approved: Bool) {
        let waiting = continuation
        continuation = nil
        pending = nil
        waiting?.resume(returning: approved)
    }
}
