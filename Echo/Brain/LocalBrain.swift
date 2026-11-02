import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// A language model that runs on this phone: the missing Tier 1. It is given exactly the request Muse would get (the same rules and
/// the same minimal snippets), but the words never leave the phone.
protocol LocalBrain: AnyObject {
    /// Whether the phone can run it at all (Apple Intelligence on, a device that supports it).
    var isAvailable: Bool { get }
    /// Answers in the same shape Muse does. Throws if the model can't run right now (not downloaded, too much text, refused).
    func answer(developer: String, user: String) async throws -> CloudAnswer
}

enum LocalBrainError: Error { case unavailable, empty }

/// Apple's on-device model (the Foundation Models framework, iOS 26 and later).
final class SystemLocalBrain: LocalBrain {
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { if case .available = SystemLanguageModel.default.availability { return true } }
        #endif
        return false
    }

    func answer(developer: String, user: String) async throws -> CloudAnswer {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let session = LanguageModelSession(model: .default, instructions: developer + "\n\nGive at most five items.")
            let response = try await session.respond(to: user, generating: GeneratedAnswer.self)
            let generated = response.content
            guard !generated.answer.isEmpty else { throw LocalBrainError.empty }
            return CloudAnswer(answer: generated.answer,
                               items: generated.items.map { CloudItem(title: $0.title, detail: $0.detail, when: $0.when, sourceTime: $0.sourceTime, source: $0.source) })
        }
        #endif
        throw LocalBrainError.unavailable
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct GeneratedAnswer {
    @Guide(description: "A direct answer of at most three sentences, grounded only in the snippets")
    var answer: String
    @Guide(description: "The things the answer is made of, each from one snippet")
    var items: [GeneratedItem]
}

@available(iOS 26.0, *)
@Generable
struct GeneratedItem {
    @Guide(description: "Short label, such as what was promised")
    var title: String
    @Guide(description: "One sentence of detail")
    var detail: String
    @Guide(description: "A due date or time that was mentioned, or an empty string")
    var when: String
    @Guide(description: "The label of the snippet this came from, like S3")
    var source: String
    @Guide(description: "The time of that snippet")
    var sourceTime: String
}
#endif

/// "Keep answers on this phone when possible": broad questions go to the on-device model instead of Muse, when it can run.
nonisolated enum OnDevicePreference {
    static let key = "echo.preferOnDevice"
}
