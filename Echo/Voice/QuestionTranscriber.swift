import Foundation

/// What came of trying to understand a spoken question.
enum QuestionTranscription: Equatable, Sendable {
    case heard(String)
    case nothingHeard
    case speechOff
    case unavailable
    case timedOut

    /// For the person who asked. Nil when it was understood.
    var message: String? {
        switch self {
        case .heard: nil
        case .nothingHeard: "I didn't catch that. Tap the mic and try again."
        case .speechOff: "Speech recognition is off. Turn it on for Echo in Settings."
        case .unavailable: "On-device speech recognition isn't available right now."
        case .timedOut: "That took too long. Try again."
        }
    }

    /// A short machine-readable reason, for the watch's reply.
    var reason: String {
        switch self {
        case .heard: "heard"
        case .nothingHeard: "nothing-heard"
        case .speechOff: "speech-off"
        case .unavailable: "unavailable"
        case .timedOut: "timed-out"
        }
    }
}

protocol QuestionTranscribing: Sendable {
    /// Understands a recorded question. The audio is written to a temporary file for the recognizer and the file is
    /// deleted before this returns, whatever the outcome: a question's audio is never kept.
    func transcribe(audio: Data) async -> QuestionTranscription
}

/// Transcribes a spoken question with Apple's on-device recognizer. Nothing leaves the phone.
struct QuestionTranscriber: QuestionTranscribing {
    var timeout: Double = 15
    /// The recognizer, replaceable in tests.
    var recognize: @Sendable (URL) async throws -> String = { try await OnDeviceASR.transcribe(url: $0) }

    func transcribe(audio: Data) async -> QuestionTranscription {
        let url = FileManager.default.temporaryDirectory.appending(path: "question-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        do { try audio.write(to: url, options: .atomic) } catch { return .unavailable }
        let recognize = self.recognize
        do {
            let text = try await Timeout.run(seconds: timeout) { try await recognize(url) }
            let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return heard.isEmpty ? .nothingHeard : .heard(heard)
        } catch is TimedOut {
            return .timedOut
        } catch OnDeviceASR.ASRError.notAuthorized {
            return .speechOff
        } catch OnDeviceASR.ASRError.unavailable {
            return .unavailable
        } catch {
            // The recognizer reports "no speech detected" as an error.
            return .nothingHeard
        }
    }
}
