import AVFoundation
import Foundation
import Observation
import os

/// A question answered (or held back) without a cloud answer on screen.
struct AskResult {
    enum Note {
        case cloudOff          // the user's kill switch is off
        case nothingMatched    // nothing relevant on the phone, so nothing was sent
        case declined          // "Review before send" was on and the user chose not to send
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
    /// Opens the "What left your phone" panel on a cloud answer. Set by the demo driver only.
    var expandSent = false
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

    /// `quiet` skips the phone's haptics, for questions asked from the watch.
    func ask(_ text: String, quiet: Bool = false) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        ledger.gate.cancel()   // a review for an older question is moot
        generation += 1
        let mine = generation
        expandSent = false
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
            if !quiet { Haptics.soft() }
            Log.pipe.info("ask \"\(question)\" -> local in \(outcome.elapsedMs, format: .fixed(precision: 1)) ms; headline: \(answer?.headline ?? "-")")
            return
        }

        let chunks = await store.all()
        let plan = TierTwoPlanner.plan(query: question, decision: decision, outcome: outcome, chunks: chunks, model: modelID,
                                       maskNames: ledger.maskNames)
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

        if ledger.reviewBeforeSend, !isStub {
            let approved = await ledger.gate.confirm(plan: plan, query: question, kind: .ask)
            guard mine == generation else { return }
            if !approved {
                var entry = LedgerEntry(query: question, tier: .cloud, reason: "You chose not to send this.")
                entry.snippets = plan.snippets
                ledger.record(entry)
                state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: localAnswer, note: .declined))
                Log.pipe.info("ask \"\(question)\" -> declined at review, nothing sent")
                return
            }
        }

        guard mine == generation else { return }   // a newer question took over while the plan was being built
        state = .sending(query: question, plan: plan, decision: decision)
        Log.pipe.info("ask \"\(question)\" -> cloud: \(plan.snippets.count) snippets, \(plan.bodyBytes) bytes, stub=\(self.isStub)")
        let result = await caller.perform(plan: plan, query: question, kind: .ask, reason: decision.reason)
        guard mine == generation else { return }

        switch result {
        case .success(let response):
            let answer = CloudAnswer.parse(response.content).restored(plan.masking)
            state = .cloudAnswered(CloudResult(query: question, outcome: outcome, decision: decision, plan: plan, answer: answer, response: response))
            if !quiet { Haptics.success() }
            Log.pipe.info("ask \"\(question)\" <- \(response.model) in \(response.latencyMs, format: .fixed(precision: 0)) ms, tokens \(response.promptTokens)/\(response.completionTokens), \(answer.items.count) items")
        case .failure(let error):
            state = .cloudFailed(CloudFailure(query: question, outcome: outcome, decision: decision, plan: plan, error: error, localAnswer: localAnswer))
            if !quiet { Haptics.warning() }
            Log.pipe.error("ask \"\(question)\" failed: \(error.localizedDescription)")
        }
    }

    /// Answers a question from the watch in a sentence or two. Runs the normal Ask flow (so the phone shows the
    /// question and its answer, and the ledger records it), then boils the result down.
    func quickAnswer(_ text: String) async -> WatchAnswer {
        let started = Date()
        await ask(text, quiet: true)
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        return Self.watchAnswer(from: state, question: text.trimmingCharacters(in: .whitespacesAndNewlines), milliseconds: ms)
    }

    /// The watch's view of a finished question. A newer question (asked on the phone meanwhile) means this one's
    /// state was overwritten, so the watch is told to try again rather than shown someone else's answer.
    static func watchAnswer(from state: State, question: String, milliseconds: Int) -> WatchAnswer {
        func brief(_ s: String) -> String { WatchAnswer.brief(s) }
        switch state {
        case .answered(let r) where r.query == question:
            switch r.note {
            case nil: return WatchAnswer(text: brief(r.answer?.headline ?? "I didn't find that in today's conversations."), source: .local, milliseconds: milliseconds)
            case .cloudOff: return WatchAnswer(text: "Cloud is off, so I can't summarize that. Turn it on in the Privacy Ledger.", source: .none, milliseconds: milliseconds)
            case .declined: return WatchAnswer(text: "Not sent. You declined on your phone.", source: .none, milliseconds: milliseconds)
            case .nothingMatched: return WatchAnswer(text: "Nothing in today's conversations matches that.", source: .none, milliseconds: milliseconds)
            }
        case .cloudAnswered(let r) where r.query == question:
            return WatchAnswer(text: brief(r.answer.answer), source: r.response.isStub ? .stub : .muse, milliseconds: milliseconds)
        case .cloudFailed(let f) where f.query == question:
            return WatchAnswer(text: f.localAnswer.map { brief($0.headline) } ?? "Muse couldn't answer just now.", source: f.localAnswer == nil ? .none : .local, milliseconds: milliseconds)
        default:
            return WatchAnswer(text: "Your phone was busy with another question. Try again.", source: .none, milliseconds: milliseconds)
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
