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
    /// True when the phone's own model wrote the answer, so nothing was sent anywhere.
    var onDevice = false
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
    /// Opens (or, when nil, closes) the history sheet. Set by the demo driver only.
    var historyRequest: HistoryRequest.Open?
    private(set) var state: State = .idle
    private(set) var recent: [String] = []
    /// Where finished questions and their answers are kept. Set by RootView; tests that don't care leave it nil.
    var history: AskHistoryModel?
    /// The earlier question this one was understood as a follow-up to; nil for a question that stands alone.
    private(set) var followUpOf: String?
    /// Replaced in tests.
    var now: () -> Date = { Date() }
    /// Which voice is the person's own, once they have said so (so "what did I promise" is about them).
    var mySpeakerID: () -> String? = { nil }
    /// Where a moment happened, once known: a place's name, or nil if it has none (set by the app).
    enum Spot: Equatable { case named(String), unnamed }
    var spotFor: (ChunkRecord) -> Spot? = { _ in nil }
    /// The phone's own language model, when it has one (set by the app).
    var brain: (any LocalBrain)?
    /// Whether to prefer it over Muse for broad questions.
    var preferOnDevice: () -> Bool = { false }
    /// True when there is no screen to show the review sheet on (Siri, Shortcuts): a question that would need Muse is not sent then.
    var headless = false
    private var thread: Thread?

    /// The last question, kept so a short follow-up can lean on it.
    private struct Thread {
        let question: String      // as typed
        let effective: String     // with the context it was asked in
        let context: String?      // what came before it, if it was a follow-up
        let at: Date
    }

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
    func ask(_ text: String, via: AskVia = .typed, quiet: Bool = false, standalone: Bool = false) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        // A short question that leans on the last one ("which of those is due first?") is searched and sent together with it.
        // Asking the same words again (a retry) keeps the context it had the first time.
        var context: String?
        if !standalone, let last = thread, now().timeIntervalSince(last.at) < FollowUp.memory, FollowUp.isFollowUp(question) || (last.question == question && last.context != nil) {
            context = last.question == question ? last.context : last.effective
        }
        let effective = context.map { FollowUp.combine(previous: $0, question: question) } ?? question
        thread = Thread(question: question, effective: effective, context: context, at: now())
        followUpOf = context.flatMap(Self.lastQuestion)
        let started = Date()
        ledger.gate.cancel()   // a review for an older question is moot
        generation += 1
        let mine = generation
        expandSent = false
        query = question
        state = .searching(question)

        // "Where was I when…?" is answered from where the watch was when it heard that, on this phone.
        if let rest = WhereQuestion.rest(of: question), await answerWhere(rest: rest, question: question, effective: effective, via: via, quiet: quiet, started: started, mine: mine) { return }

        let outcome = await retriever.search(effective)
        let decision = Router.route(query: effective, outcome: outcome)
        recent.removeAll { $0 == question }
        recent.insert(question, at: 0)

        if decision.tier == .local {
            let answer = AnswerExtractor.extract(from: outcome)
            ledger.record(LedgerEntry(query: effective, tier: .local, reason: decision.reason))
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
        let plan = TierTwoPlanner.plan(query: effective, decision: decision, outcome: outcome, chunks: chunks, model: modelID,
                                       maskNames: ledger.maskNames, followUp: context != nil, mySpeakerId: mySpeakerID())
        let localAnswer = AnswerExtractor.extract(from: outcome)

        // The phone's own model answers when asked to (or when the cloud is off), if it can run; otherwise the usual way.
        if plan.canCall, let brain, brain.isAvailable, preferOnDevice() || !ledger.cloudEnabled,
           await answerOnDevice(brain: brain, plan: plan, question: question, effective: effective, outcome: outcome, decision: decision,
                                via: via, quiet: quiet, started: started, mine: mine, chunks: chunks) { return }

        guard ledger.cloudEnabled else {
            ledger.record(LedgerEntry(query: effective, tier: .cloud, reason: "Cloud is off, so nothing was sent."))
            guard mine == generation else { return }
            state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: localAnswer, note: .cloudOff))
            await remember(question, via: via, source: .none, short: "Cloud is off, so Muse couldn't answer.",
                           detail: noteDetail("Cloud is off, so nothing was sent.", local: localAnswer), since: started)
            Log.pipe.info("ask \"\(question)\" -> cloud needed but switched off")
            return
        }
        guard plan.canCall else {
            ledger.record(LedgerEntry(query: effective, tier: .cloud, reason: "Nothing matched closely enough, so nothing was sent."))
            guard mine == generation else { return }
            state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: localAnswer, note: .nothingMatched))
            await remember(question, via: via, source: .none, short: "Nothing in today's conversations matches that.",
                           detail: noteDetail("Nothing matched closely enough, so nothing was sent.", local: localAnswer), since: started)
            Log.pipe.info("ask \"\(question)\" -> nothing to send")
            return
        }

        if ledger.reviewBeforeSend, !isStub {
            let approved = headless ? false : await ledger.gate.confirm(plan: plan, query: effective, kind: .ask)
            guard mine == generation else { return }
            if !approved {
                var entry = LedgerEntry(query: effective, tier: .cloud, reason: headless ? "Review before send is on and there was no screen to review on, so nothing was sent." : "You chose not to send this.")
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
        let result = await caller.perform(plan: plan, query: effective, kind: .ask, reason: context == nil ? decision.reason : "Follow-up. " + decision.reason)
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

    /// Asks the on-device model. False if it couldn't answer (the caller carries on without it).
    private func answerOnDevice(brain: any LocalBrain, plan: TierTwoPlan, question: String, effective: String, outcome: RetrievalOutcome,
                                decision: RouteDecision, via: AskVia, quiet: Bool, started: Date, mine: Int, chunks: [ChunkRecord]) async -> Bool {
        state = .searching(question)
        let t0 = Date()
        guard let raw = try? await brain.answer(developer: plan.request.developer, user: plan.request.user) else { return false }
        guard mine == generation else { return true }
        let answer = raw.restored(plan.masking)
        let ms = Date().timeIntervalSince(t0) * 1000
        var entry = LedgerEntry(query: effective, tier: .onDevice, reason: "Answered by the on-device model on this phone, so nothing was sent.")
        entry.snippets = plan.snippets
        entry.model = "on-device"
        entry.leftDevice = false
        entry.bodyBytes = 0
        entry.maskedNames = plan.maskedCount
        entry.latencyMs = ms
        entry.status = .ok
        ledger.record(entry)
        let content = (try? String(data: JSONEncoder().encode(answer), encoding: .utf8)) ?? answer.answer
        let response = MuseResponse(content: content, model: "On-device model", promptTokens: 0, completionTokens: 0, latencyMs: ms, isStub: false)
        let local = RouteDecision(tier: .onDevice, reason: "Answered by the on-device model, so nothing left this phone.", signals: decision.signals, intent: decision.intent)
        recent.removeAll { $0 == question }
        recent.insert(question, at: 0)
        state = .cloudAnswered(CloudResult(query: question, outcome: outcome, decision: local, plan: plan, answer: answer, response: response, onDevice: true))
        if !quiet { Haptics.success() }
        let items = answer.items.map { item in
            AskDetail.Item(title: item.title, detail: item.detail, when: item.when, sourceTime: item.sourceTime,
                           chunkID: CitationResolver.resolve(source: item.source, sourceTime: item.sourceTime, detail: item.detail + " " + item.title,
                                                             snippets: plan.snippets, chunks: chunks)?.id)
        }
        await remember(question, via: via, source: .local, short: answer.answer, detail: AskDetail(kind: .cloud, headline: answer.answer, items: items), since: started)
        return true
    }

    /// The moment `rest` describes, and where it happened. False if nothing like it has a place, so the question goes the usual way.
    private func answerWhere(rest: String, question: String, effective: String, via: AskVia, quiet: Bool, started: Date, mine: Int) async -> Bool {
        let outcome = await retriever.search(rest)
        guard let hit = outcome.hits.first(where: { $0.chunk.coordinate != nil }), let spot = spotFor(hit.chunk) else { return false }
        let headline: String
        switch spot {
        case .named(let name): headline = "You were at \(name)."
        case .unnamed: headline = "You were at a place you haven't named yet. You can name it under Places on Today."
        }
        let answer = Answer(headline: headline, headlineChunk: hit.chunk, sources: [hit], highlightTerms: outcome.knownTerms)
        let decision = RouteDecision(tier: .local, reason: "Worked out from where the watch was when it heard that, on this phone.", signals: ["where"])
        ledger.record(LedgerEntry(query: effective, tier: .local, reason: decision.reason))
        guard mine == generation else { return true }
        recent.removeAll { $0 == question }
        recent.insert(question, at: 0)
        state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: answer))
        if !quiet { Haptics.soft() }
        await remember(question, via: via, source: .local, short: headline,
                       detail: AskDetail(kind: .local, headline: headline, sourceChunkIDs: [hit.chunk.id], terms: outcome.knownTerms), since: started)
        return true
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
            return WatchAnswer(text: brief(r.answer.answer), source: r.onDevice ? .local : (r.response.isStub ? .stub : .muse), milliseconds: milliseconds)
        case .cloudFailed(let f) where f.query == question:
            return WatchAnswer(text: f.localAnswer.map { brief($0.headline) } ?? "Muse couldn't answer just now.", source: f.localAnswer == nil ? .none : .local, milliseconds: milliseconds)
        default:
            return WatchAnswer(text: "Your phone was busy with another question. Try again.", source: .none, milliseconds: milliseconds)
        }
    }

    /// True once a question has an answer (or a reason it has none) on screen, not while one is still being worked on.
    var isFinishedAsking: Bool {
        switch state {
        case .idle, .searching, .sending: false
        default: true
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

    /// The last question of a (possibly combined) text: what a follow-up chip names.
    private static func lastQuestion(_ text: String) -> String? {
        let parts = text.split(separator: "?", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return parts.last.map { $0 + (text.contains("?") ? "?" : "") }
    }

    /// Ends the conversation: the next question stands alone.
    func startFresh() {
        thread = nil
        followUpOf = nil
    }

    func clear() {
        generation += 1
        thread = nil
        followUpOf = nil
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
