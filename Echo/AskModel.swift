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
    /// Scrolls the Ask tab to an anchor ("items", "sentPanel", "askTop"). Set by the demo driver only.
    var scrollTarget: String?
    private(set) var state: State = .idle
    private(set) var recent: [String] = []
    /// Where finished questions and their answers are kept. Set by RootView; tests that don't care leave it nil.
    var history: AskHistoryModel?

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

    /// Saves a finished question to the history, if there is one.
    private func remember(_ question: String, via: AskVia, source: WatchAnswer.Source, short: String, detail: AskDetail, since started: Date) async {
        guard let history else { return }
        await history.record(AskRecord(question: question, shortAnswer: WatchAnswer.brief(short), source: source, via: via, detail: detail,
                                       milliseconds: Int(Date().timeIntervalSince(started) * 1000)))
    }

    /// A history detail for an answer that is not an answer: why nothing came back, plus the closest local moment if any.
    private func noteDetail(_ note: String, local: Answer?) -> AskDetail {
        AskDetail(kind: .note, headline: local?.headline ?? "", sourceChunkIDs: local?.sources.map { $0.chunk.id } ?? [],
                  terms: local?.highlightTerms ?? [], note: note)
    }

    /// `via` is how it was asked (kept in the history). `quiet` skips the phone's haptics, for questions from the watch.
    func ask(_ text: String, via: AskVia = .typed, quiet: Bool = false) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let started = Date()
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
            await remember(question, via: via, source: .local, short: answer?.headline ?? "I didn't find that in today's conversations.",
                           detail: AskDetail(kind: .local, headline: answer?.headline ?? "", sourceChunkIDs: answer?.sources.map { $0.chunk.id } ?? [],
                                             terms: answer?.highlightTerms ?? []), since: started)
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
            await remember(question, via: via, source: .none, short: "Cloud is off, so Muse couldn't answer.",
                           detail: noteDetail("Cloud is off, so nothing was sent.", local: localAnswer), since: started)
            Log.pipe.info("ask \"\(question)\" -> cloud needed but switched off")
            return
        }
        guard plan.canCall else {
            ledger.record(LedgerEntry(query: question, tier: .cloud, reason: "Nothing matched closely enough, so nothing was sent."))
            guard mine == generation else { return }
            state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: localAnswer, note: .nothingMatched))
            await remember(question, via: via, source: .none, short: "Nothing in today's conversations matches that.",
                           detail: noteDetail("Nothing matched closely enough, so nothing was sent.", local: localAnswer), since: started)
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
                await remember(question, via: via, source: .none, short: "You chose not to send this to Muse.",
                               detail: noteDetail("You chose not to send this.", local: localAnswer), since: started)
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
            let items = answer.items.map { item in
                AskDetail.Item(title: item.title, detail: item.detail, when: item.when, sourceTime: item.sourceTime,
                               chunkID: CitationResolver.resolve(source: item.source, sourceTime: item.sourceTime, detail: item.detail + " " + item.title,
                                                                 snippets: plan.snippets, chunks: chunks)?.id)
            }
            await remember(question, via: via, source: response.isStub ? .stub : .muse, short: answer.answer,
                           detail: AskDetail(kind: .cloud, headline: answer.answer, items: items), since: started)
            Log.pipe.info("ask \"\(question)\" <- \(response.model) in \(response.latencyMs, format: .fixed(precision: 0)) ms, tokens \(response.promptTokens)/\(response.completionTokens), \(answer.items.count) items")
        case .failure(let error):
            state = .cloudFailed(CloudFailure(query: question, outcome: outcome, decision: decision, plan: plan, error: error, localAnswer: localAnswer))
            if !quiet { Haptics.warning() }
            await remember(question, via: via, source: localAnswer == nil ? .none : .local,
                           short: localAnswer?.headline ?? "Muse couldn't answer just now.",
                           detail: noteDetail("Muse couldn't answer: \(error.localizedDescription)", local: localAnswer), since: started)
            Log.pipe.error("ask \"\(question)\" failed: \(error.localizedDescription)")
        }
    }

    /// Answers a question from the watch in a sentence or two. Runs the normal Ask flow (so the phone shows the
    /// question and its answer, and the ledger records it), then boils the result down.
    func quickAnswer(_ text: String, via: AskVia = .watch) async -> WatchAnswer {
        let started = Date()
        await ask(text, via: via, quiet: true)
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

    /// The answer on screen as plain text to read aloud, or nil while there isn't one yet.
    var spokenAnswer: String? {
        switch state {
        case .idle, .searching, .sending: return nil
        case .answered(let r):
            switch r.note {
            case nil: return r.answer?.headline ?? "I didn't find that in today's conversations."
            case .cloudOff: return "Cloud is off, so I can't summarize that. Turn it on in the Privacy tab."
            case .declined: return "Not sent. You chose not to send that to Muse."
            case .nothingMatched: return "Nothing in today's conversations matches that."
            }
        case .cloudAnswered(let r): return r.answer.answer
        case .cloudFailed(let f): return f.localAnswer?.headline ?? "Muse couldn't answer just now."
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
    /// Called just before a moment starts playing, so a spoken answer can stop.
    var willPlay: (() -> Void)?
    private var player: AVAudioPlayer?
    private let directory: URL

    init(directory: URL) { self.directory = directory }

    func toggle(_ chunk: ChunkRecord) {
        if playingID == chunk.id { stop(); return }
        stop()
        willPlay?()
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
