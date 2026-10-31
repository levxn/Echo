import Foundation
import os
import Speech

/// On-device speech recognition for a stored chunk (no audio leaves the phone).
nonisolated enum OnDeviceASR {
    enum ASRError: Error { case unavailable, notAuthorized }

    @MainActor
    static func authorize() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    static func transcribe(url: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw ASRError.notAuthorized }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { throw ASRError.unavailable }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        return try await withCheckedThrowingContinuation { cont in
            let lock = OSAllocatedUnfairLock(initialState: false)
            func finish(_ result: Swift.Result<String, Error>) {
                let already = lock.withLock { done -> Bool in let was = done; done = true; return was }
                guard !already else { return }
                cont.resume(with: result)
            }
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    finish(.success(result.bestTranscription.formattedString))
                } else if let error {
                    finish(.failure(error))
                }
            }
        }
    }
}
