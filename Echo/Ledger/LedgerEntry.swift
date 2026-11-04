import Foundation

/// One question and where it was answered. Local answers are logged too, with zero bytes sent, so the
/// ledger shows the whole picture: what stayed on the phone and what did not.
struct LedgerEntry: Identifiable, Equatable {
    enum Kind: String { case ask, digest, draft, journal }
    enum Status: String { case pending, ok, error }

    var id = UUID().uuidString
    var timestamp = Date()
    var kind: Kind = .ask
    var query: String
    var tier: Tier
    var reason = ""
    var leftDevice = false
    var model = ""
    var isStub = false
    /// Exactly the text that was sent (time and words only).
    var snippets: [Snippet] = []
    /// Size of the HTTP body that was transmitted. Zero for local answers and for requests that never left.
    var bodyBytes = 0
    /// The reply Muse returned (raw structured JSON), kept so the ledger can show it.
    var response = ""
    var promptTokens = 0
    var completionTokens = 0
    var latencyMs = 0.0
    /// People's names replaced with placeholders before sending (`snippets` shows the masked text that left).
    var maskedNames = 0
    /// Confidential details (passwords, codes, numbers) held back on the phone, by kind name. Counts only, never the values.
    var heldBack: [String: Int] = [:]
    var heldBackCount: Int { heldBack.values.reduce(0, +) }
    var status: Status = .ok
    var error = ""
}

/// Roll-up shown at the top of the ledger.
struct LedgerTotals: Equatable {
    var questions = 0
    /// Questions where nothing was sent: local answers, stubs, a cloud switch that was off, requests that never left.
    var stayedOnPhone = 0
    var usedMuse = 0
    var bytesSent = 0
    var snippetsSent = 0

    init(_ entries: [LedgerEntry]) {
        let asks = entries.filter { $0.kind == .ask }
        questions = asks.count
        stayedOnPhone = asks.filter { !$0.leftDevice }.count
        usedMuse = entries.filter { $0.leftDevice && $0.status == .ok && !$0.isStub }.count
        bytesSent = entries.filter { $0.leftDevice }.reduce(0) { $0 + $1.bodyBytes }
        snippetsSent = entries.filter { $0.leftDevice && $0.bodyBytes > 0 }.reduce(0) { $0 + $1.snippets.count }
    }
}
