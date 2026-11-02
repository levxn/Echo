import Foundation

/// What the phone does when the watch asks it something: understand a recorded question, answer a question, or send
/// the recent history. Kept apart from WatchConnectivity so it can be tested.
@MainActor
struct WatchRequests {
    var transcriber: any QuestionTranscribing
    /// Answers a question (the phone also shows it and logs it).
    var answer: (String, AskVia) async -> WatchAnswer
    var history: () -> [HistoryItem]
    /// Whether answers to spoken questions should be read aloud (the person's setting on this phone).
    var speakVoiceAnswers: () -> Bool = { false }
    /// Forgets the last N minutes of what was heard; says how many moments went.
    var forgetRecent: (Int) async -> Int = { _ in 0 }
    /// Sets a reminder for a promise the watch just showed; says whether it worked.
    var keepPromise: (String) async -> Bool = { _ in false }

    /// Nil when the message isn't one of these, so the caller can try something else.
    func handle(_ message: [String: Any]) async -> [String: Any]? {
        switch message[Wire.typeKey] as? String {
        case Wire.ask:
            guard let question = (message[Wire.questionKey] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !question.isEmpty else {
                return [Wire.okKey: false, Wire.reasonKey: "no-question"]
            }
            let via = (message[Wire.viaKey] as? String).flatMap(AskVia.init) ?? .watch
            var reply = await answer(question, via)
            if via.isVoice && speakVoiceAnswers() { reply.speak = true }
            return reply.dictionary

        case Wire.transcribe:
            guard let audio = message[Wire.audioKey] as? Data, !audio.isEmpty else { return [Wire.okKey: false, Wire.reasonKey: "nothing-heard"] }
            switch await transcriber.transcribe(audio: audio) {
            case .heard(let text): return [Wire.okKey: true, Wire.heardKey: text]
            case let other: return [Wire.okKey: false, Wire.reasonKey: other.reason]
            }

        case Wire.history:
            return [Wire.okKey: true, Wire.itemsKey: history().prefix(HistoryCache.limit).map(\.dictionary)]

        case Wire.keepPromise:
            guard let id = message[Wire.idKey] as? String else { return [Wire.okKey: false] }
            return [Wire.okKey: await keepPromise(id)]

        case Wire.forget:
            let minutes = min(120, max(1, message[Wire.minutesKey] as? Int ?? 10))
            return [Wire.okKey: true, Wire.countKey: await forgetRecent(minutes)]

        default:
            return nil
        }
    }
}
