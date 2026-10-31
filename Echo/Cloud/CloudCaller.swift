import Foundation

/// Makes one cloud call and keeps the privacy ledger truthful about it: a pending row before the request,
/// then the outcome. A stub never leaves the phone, and a request that fails before reaching Meta
/// (offline) records zero bytes.
@MainActor
final class CloudCaller {
    let client: any MuseClient
    let ledger: LedgerModel

    init(client: any MuseClient, ledger: LedgerModel) {
        self.client = client
        self.ledger = ledger
    }

    func perform(plan: TierTwoPlan, query: String, kind: LedgerEntry.Kind, reason: String) async -> Result<MuseResponse, MuseError> {
        var entry = LedgerEntry(query: query, tier: .cloud, reason: reason)
        entry.kind = kind
        entry.isStub = client.isStub
        entry.model = client.isStub ? "stub" : plan.request.model
        entry.snippets = plan.snippets
        entry.maskedNames = plan.maskedCount
        entry.leftDevice = !client.isStub
        entry.bodyBytes = client.isStub ? 0 : plan.bodyBytes
        entry.status = .pending
        ledger.record(entry)

        do {
            let response = try await client.complete(plan.request)
            entry.status = .ok
            entry.model = response.model
            entry.response = response.content
            entry.promptTokens = response.promptTokens
            entry.completionTokens = response.completionTokens
            entry.latencyMs = response.latencyMs
            ledger.record(entry)
            return .success(response)
        } catch {
            let museError = error as? MuseError ?? .server(-1, error.localizedDescription)
            entry.status = .error
            entry.error = APIKeyStore.redacted(museError.localizedDescription, key: APIKeyStore.load())
            if museError == .offline { entry.bodyBytes = 0; entry.leftDevice = false }   // it never reached Meta
            ledger.record(entry)
            return .failure(museError)
        }
    }
}
