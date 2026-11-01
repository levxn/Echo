import Foundation
import Observation
import SwiftUI

/// Asking the phone out loud: listen for a question, understand it on this phone, then ask it like any typed one.
/// Tapping the mic again while it listens ends the recording early. In a simulator a recorded question stands in for
/// the microphone and says so.
@MainActor
@Observable
final class VoiceAskModel {
    /// Why a spoken question didn't work, and whether the fix is in Settings.
    struct Problem: Equatable {
        var message: String
        var needsSettings = false
    }

    enum State: Equatable {
        case idle
        case listening
        case understanding
        case problem(Problem)
    }

    private(set) var state = State.idle
    let recorder: QuestionRecorder
    private let transcriber: any QuestionTranscribing
    private let source: (Int) -> QuestionRecorder.Source
    /// Which recorded question comes next in a simulator.
    private var count = 0
    private var generation = 0

    /// `source` picks what to record from (a recorded clip or the microphone) for the nth question; tests replace it.
    init(recorder: QuestionRecorder? = nil, transcriber: (any QuestionTranscribing)? = nil,
         source: ((Int) -> QuestionRecorder.Source)? = nil) {
        self.recorder = recorder ?? QuestionRecorder()
        self.transcriber = transcriber ?? QuestionTranscriber()
        self.source = source ?? { QuestionRecorder.defaultSource(next: $0) }
    }

    var isBusy: Bool { state == .listening || state == .understanding }

    /// A new question can begin when nothing is in progress (a problem from the last try doesn't count).
    private var canStart: Bool {
        if case .problem = state { return true }
        return state == .idle
    }

    /// Listens, understands and asks. Returns the question that was asked, or nil if nothing was (the reason is in
    /// `state`). `clip` picks which recorded question (1...5) stands in for the microphone in a simulator.
    @discardableResult
    func listen(clip: Int? = nil, ask: AskModel) async -> String? {
        if state == .listening { recorder.stop(); return nil }
        guard canStart else { return nil }
        generation += 1
        let mine = generation
        // A recording that was just cancelled may still be winding down.
        for _ in 0..<20 where recorder.phase != .idle { try? await Task.sleep(for: .milliseconds(50)) }
        state = .listening
        Haptics.soft()
        AccessibilityNotification.Announcement("Listening. Ask your question.").post()
        let index = clip.map { $0 - 1 } ?? count
        count += 1
        let result = await recorder.record(source(index))
        guard mine == generation else { return nil }
        switch result {
        case .failure(let error):
            fail(Problem(message: error.message, needsSettings: error == .microphoneDenied))
            return nil
        case .success(let clip):
            state = .understanding
            let heard = await transcriber.transcribe(audio: clip.audio)
            guard mine == generation else { return nil }
            guard case .heard(let text) = heard else {
                fail(Problem(message: heard.message ?? "I couldn't understand that.", needsSettings: heard == .speechOff))
                return nil
            }
            state = .idle
            AccessibilityNotification.Announcement("Heard: \(text)").post()
            await ask.ask(text, via: .voice)
            return text
        }
    }

    /// Stops listening and forgets the question (the Cancel button).
    func cancel() {
        generation += 1
        recorder.stop()
        state = .idle
    }

    func dismissProblem() {
        if case .problem = state { state = .idle }
    }

    private func fail(_ problem: Problem) {
        state = .problem(problem)
        Haptics.warning()
        AccessibilityNotification.Announcement(problem.message).post()
    }
}
