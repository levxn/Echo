import Foundation
import Observation

/// "Summarize my day with Muse": one structured call over the whole day, saved so it survives restarts.
@MainActor
@Observable
final class DigestModel {
    struct Ready {
        let digest: DayDigest
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

    func load() async {
        if let saved = await store.loadDigest(), let digest = DayDigest.parse(saved.json) {
            state = .ready(Ready(digest: digest, model: saved.model, isStub: saved.isStub))
        } else {
            state = .idle
        }
    }

    func generate(chunks: [ChunkRecord]) async {
        guard ledger.cloudEnabled else { state = .cloudOff; return }
        let plan = TierTwoPlanner.digestPlan(chunks: chunks, model: modelID, maskNames: ledger.maskNames)
        guard plan.canCall else { return }
        if ledger.reviewBeforeSend, !isStub {
            let approved = await ledger.gate.confirm(plan: plan, query: "Summarize my day with Muse", kind: .digest)
            if !approved {
                var entry = LedgerEntry(query: "Summarize my day with Muse", tier: .cloud, reason: "You chose not to send this.")
                entry.kind = .digest
                entry.snippets = plan.snippets
                ledger.record(entry)
                state = .idle
                return
            }
        }
        state = .working(plan)
        let result = await caller.perform(plan: plan, query: "Summarize my day with Muse", kind: .digest,
                                          reason: "You asked Muse to summarize the whole day.")
        switch result {
        case .success(let response):
            guard let parsed = DayDigest.parse(response.content) else {
                state = .failed("Muse's digest couldn't be read. Try again.")
                return
            }
            // Names come back before anything is shown or saved, so a reload after a relaunch needs no mapping.
            let digest = parsed.restored(plan.masking)
            let json = plan.masking.isEmpty ? response.content
                : ((try? String(data: JSONEncoder().encode(digest), encoding: .utf8)) ?? response.content)
            await store.saveDigest(json: json, model: response.model, isStub: response.isStub)
            state = .ready(Ready(digest: digest, model: response.model, isStub: response.isStub))
        case .failure(let error):
            state = .failed(error.localizedDescription)
        }
    }

    /// The day was cleared, so its digest no longer describes anything.
    func reset() { state = .idle }
}
