import Foundation

/// What the phone does when the watch asks it something: understand a recorded question, answer a question, or send
/// the recent history. Kept apart from WatchConnectivity so it can be tested.
@MainActor
struct WatchRequests {
    var transcriber: any QuestionTranscribing
    /// Answers a question (the phone also shows it and logs it).
    var answer: (String, AskVia) async -> WatchAnswer
    var history: () -> [HistoryItem]

    /// Nil when the message isn't one of these, so the caller can try something else.
    func handle(_ message: [String: Any]) async -> [String: Any]? {
        switch message[Wire.typeKey] as? String {
        case Wire.ask:
            guard let question = (message[Wire.questionKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else {
                return [Wire.okKey: false, Wire.reasonKey: "no-question"]
            }
            let via = (message[Wire.viaKey] as? String).flatMap(AskVia.init) ?? .watch
            return await answer(question, via).dictionary

        case Wire.transcribe:
            guard let audio = message[Wire.audioKey] as? Data, !audio.isEmpty else { return [Wire.okKey: false, Wire.reasonKey: "nothing-heard"] }
            switch await transcriber.transcribe(audio: audio) {
            case .heard(let text): return [Wire.okKey: true, Wire.heardKey: text]
            case let other: return [Wire.okKey: false, Wire.reasonKey: other.reason]
            }

        case Wire.history:
            return [Wire.okKey: true, Wire.itemsKey: history().prefix(HistoryCache.limit).map(\.dictionary)]

        default:
            return nil
        }
    }
}
