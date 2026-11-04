import Foundation
import Observation

/// "Find more with Muse": the day's moments go to Muse as text (after anything confidential has been swapped for a placeholder on the
/// phone), through the review gate and the ledger like every other request. What comes back is checked against the real moments.
@MainActor
@Observable
final class MuseActionsModel {
    enum State: Equatable {
        case idle
        case working(snippets: Int, heldBack: Int)
        case done(found: Int, isStub: Bool)
        case declined
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

    /// Looks through `day` for things the rules missed, and adds them to the list. Returns how many were new.
    @discardableResult
    func find(chunks: [ChunkRecord], day: String, actions: ActionsModel, userName: String, myVoice: String?, voiceNames: [String: String]) async -> Int {
        guard ledger.cloudEnabled else { state = .cloudOff; return 0 }
        let plan = TierTwoPlanner.actionsPlan(chunks: chunks, day: day, model: modelID, maskNames: ledger.maskNames)
        guard plan.canCall else { state = .failed("There is nothing from today on this phone yet."); return 0 }
        let query = "Find things to act on in today's moments"
        if ledger.reviewBeforeSend, !isStub {
            let approved = await ledger.gate.confirm(plan: plan, query: query, kind: .actions)
            if !approved {
                var entry = LedgerEntry(query: query, tier: .cloud, reason: "You chose not to send this.")
                entry.kind = .actions
                entry.snippets = plan.snippets
                ledger.record(entry)
                state = .declined
                return 0
            }
        }
        state = .working(snippets: plan.snippets.count, heldBack: plan.heldBackCount)
        switch await caller.perform(plan: plan, query: query, kind: .actions, reason: "You asked Muse to look for more things to act on.") {
        case .success(let response):
            guard let list = MuseActionList.parse(response.content) else { state = .failed("Muse's list couldn't be read. Try again."); return 0 }
            let found = MuseActionMapper.items(from: list, snippets: plan.snippets, chunks: chunks, masking: plan.masking, now: Date())
            let before = actions.items.filter { $0.origin == .muse }.count
            await actions.addFromMuse(found, model: response.model, chunks: chunks, userName: userName, myVoice: myVoice, voiceNames: voiceNames)
            let added = max(0, actions.items.filter { $0.origin == .muse }.count - before)
            state = .done(found: added, isStub: response.isStub)
            return added
        case .failure(let error):
            state = .failed(error.localizedDescription)
            return 0
        }
    }

    func reset() { state = .idle }
}
