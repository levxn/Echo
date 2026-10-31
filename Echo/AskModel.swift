import AVFoundation
import Foundation
import Observation
import os

/// A question answered (or held back) without a cloud answer on screen.
struct AskResult {
    enum Note {
        case cloudOff          // the user's kill switch is off
        case nothingMatched    // nothing relevant on the phone, so nothing was sent
    }

    let query: String
    let outcome: RetrievalOutcome
    let decision: RouteDecision
    /// The local extractive answer, when there is one.
    let answer: Answer?
    var note: Note?
}

struct CloudResult {
    let query: String
    let outcome: RetrievalOutcome
    let decision: RouteDecision
    let plan: TierTwoPlan
    let answer: CloudAnswer
    let response: MuseResponse
}

struct CloudFailure {
    let query: String
    let outcome: RetrievalOutcome
    let decision: RouteDecision
    let plan: TierTwoPlan
    let error: MuseError
    /// Local fallback so a failed call never leaves the screen empty.
    let localAnswer: Answer?
}

/// Runs a question through retrieval and the router, answers locally or calls Muse, and logs every
/// outcome to the privacy ledger.
@MainActor
@Observable
final class AskModel {
    enum State {
        case idle
        case searching(String)
        case answered(AskResult)
        case sending(query: String, plan: TierTwoPlan, decision: RouteDecision)
        case cloudAnswered(CloudResult)
        case cloudFailed(CloudFailure)
    }

    var query = ""
    private(set) var state: State = .idle
    private(set) var recent: [String] = []

    private let retriever: Retriever
    private let caller: CloudCaller
    private let ledger: LedgerModel
    let store: ChunkStore
    private let modelID: String
    /// Guards against a slow earlier answer overwriting a newer question.
    private var generation = 0

    init(store: ChunkStore, ledger: LedgerModel, client: any MuseClient, model: String = MuseClientFactory.model) {
        self.store = store
        self.ledger = ledger
        self.retriever = Retriever(store: store)
        self.caller = CloudCaller(client: client, ledger: ledger)
        self.modelID = model
    }

    /// True when the client is the offline stand-in (no API key).
    var isStub: Bool { caller.client.isStub }

    func ask(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        generation += 1
        let mine = generation
        query = question
        state = .searching(question)

        let outcome = await retriever.search(question)
        let decision = Router.route(query: question, outcome: outcome)
        recent.removeAll { $0 == question }
        recent.insert(question, at: 0)

        if decision.tier == .local {
            let answer = AnswerExtractor.extract(from: outcome)
            ledger.record(LedgerEntry(query: question, tier: .local, reason: decision.reason))
            guard mine == generation else { return }
            state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: answer))
            Log.pipe.info("ask \"\(question)\" -> local in \(outcome.elapsedMs, format: .fixed(precision: 1)) ms; headline: \(answer?.headline ?? "-")")
            return
        }

        let chunks = await store.all()
        let plan = TierTwoPlanner.plan(query: question, decision: decision, outcome: outcome, chunks: chunks, model: modelID)
        let localAnswer = AnswerExtractor.extract(from: outcome)

        guard ledger.cloudEnabled else {
            ledger.record(LedgerEntry(query: question, tier: .cloud, reason: "Cloud is off, so nothing was sent."))
            guard mine == generation else { return }
            state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: localAnswer, note: .cloudOff))
            Log.pipe.info("ask \"\(question)\" -> cloud needed but switched off")
            return
        }
        guard plan.canCall else {
            ledger.record(LedgerEntry(query: question, tier: .cloud, reason: "Nothing matched closely enough, so nothing was sent."))
            guard mine == generation else { return }
            state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: localAnswer, note: .nothingMatched))
            Log.pipe.info("ask \"\(question)\" -> nothing to send")
            return
        }

        state = .sending(query: question, plan: plan, decision: decision)
        Log.pipe.info("ask \"\(question)\" -> cloud: \(plan.snippets.count) snippets, \(plan.bodyBytes) bytes, stub=\(self.isStub)")
        let result = await caller.perform(plan: plan, query: question, kind: .ask, reason: decision.reason)
        guard mine == generation else { return }

        switch result {
        case .success(let response):
            let answer = CloudAnswer.parse(response.content)
            state = .cloudAnswered(CloudResult(query: question, outcome: outcome, decision: decision, plan: plan, answer: answer, response: response))
            Log.pipe.info("ask \"\(question)\" <- \(response.model) in \(response.latencyMs, format: .fixed(precision: 0)) ms, tokens \(response.promptTokens)/\(response.completionTokens), \(answer.items.count) items")
        case .failure(let error):
            state = .cloudFailed(CloudFailure(query: question, outcome: outcome, decision: decision, plan: plan, error: error, localAnswer: localAnswer))
            Log.pipe.error("ask \"\(question)\" failed: \(error.localizedDescription)")
        }
    }

    func retry() async {
        let q: String
        switch state {
        case .cloudFailed(let f): q = f.query
        default: q = query
        }
        await ask(q)
    }

    func clear() {
        generation += 1
        query = ""
        state = .idle
    }
}

/// Plays a stored chunk so an answer can be checked against the audio it came from.
@MainActor
@Observable
final class ChunkPlayer {
    private(set) var playingID: String?
    private var player: AVAudioPlayer?
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    func toggle(_ chunk: ChunkRecord) {
        if playingID == chunk.id { stop(); return }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: directory.appending(path: chunk.audioFile))
            player.play()
            self.player = player
            playingID = chunk.id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(player.duration + 0.2))
                if self?.playingID == chunk.id { self?.stop() }
            }
        } catch {
            Log.app.error("playback failed: \(error.localizedDescription)")
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }
}
