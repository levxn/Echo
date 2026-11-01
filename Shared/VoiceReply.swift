import Foundation

/// The phone's answer to "here is a recorded question": what it understood, or why it didn't.
nonisolated enum VoiceReply: Equatable, Sendable {
    case heard(String)
    case failed(reason: String)
    case unreachable

    /// nil means the phone didn't answer at all.
    init(dictionary: [String: Any]?) {
        guard let d = dictionary else { self = .unreachable; return }
        if d[Wire.okKey] as? Bool == true, let heard = d[Wire.heardKey] as? String, !heard.isEmpty { self = .heard(heard) }
        else { self = .failed(reason: d[Wire.reasonKey] as? String ?? "unavailable") }
    }

    /// For the person who asked. Nil when it was understood.
    var message: String? {
        switch self {
        case .heard: nil
        case .unreachable: "Phone not reachable. Is Echo open on your phone?"
        case .failed(let reason):
            switch reason {
            case "nothing-heard": "I didn't catch that. Tap the mic and try again."
            case "speech-off": "Speech recognition is off on your phone."
            case "timed-out": "That took too long. Try again."
            default: "Your phone can't understand speech right now."
            }
        }
    }
}
