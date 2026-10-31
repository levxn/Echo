import AVFoundation
import Foundation
import Observation
import os

struct AskResult {
    let query: String
    let outcome: RetrievalOutcome
    let decision: RouteDecision
    /// Present for Tier 0 answers.
    let answer: Answer?
}

/// Runs a question through retrieval and the router, and exposes the result to the Ask screen.
@MainActor
@Observable
final class AskModel {
    enum State {
        case idle
        case searching(String)
        case answered(AskResult)
    }

    var query = ""
    private(set) var state: State = .idle
    private(set) var recent: [String] = []

    private let retriever: Retriever
    let store: ChunkStore

    init(store: ChunkStore) {
        self.store = store
        retriever = Retriever(store: store)
    }

    func ask(_ text: String) async {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        query = question
        state = .searching(question)
        let outcome = await retriever.search(question)
        let decision = Router.route(query: question, outcome: outcome)
        let answer = decision.tier == .local ? AnswerExtractor.extract(from: outcome) : nil
        recent.removeAll { $0 == question }
        recent.insert(question, at: 0)
        state = .answered(AskResult(query: question, outcome: outcome, decision: decision, answer: answer))
        Log.pipe.info("ask \"\(question)\" -> \(decision.tier.rawValue) in \(outcome.elapsedMs, format: .fixed(precision: 1)) ms; top: \(outcome.hits.first?.chunk.transcript ?? "-"); headline: \(answer?.headline ?? "-")")
    }

    func clear() {
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
