import Foundation
import Observation

/// What the person has said about being recorded: whether Echo is off the record right now, and whether the watch should
/// announce that it is listening.
@MainActor
@Observable
final class RecordingPrivacy {
    static let announceKey = "echo.announceRecording"

    private(set) var gate = PrivacyGate()
    /// The watch buzzes every ten minutes while it listens, so people nearby aren't unaware.
    var announce: Bool {
        didSet {
            defaults.set(announce, forKey: Self.announceKey)
            if announce != oldValue { onAnnounceChanged?(announce) }
        }
    }
    /// Told when the setting changes (the app passes it to the watch).
    var onAnnounceChanged: ((Bool) -> Void)?
    private let defaults: UserDefaults
    private let now: () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        announce = defaults.bool(forKey: Self.announceKey)
    }

    var isOffTheRecord: Bool { gate.isPrivate(now: now()) }

    /// For the pipeline: what to do with something just understood.
    func decide(transcript: String?) -> PrivacyGate.Decision {
        var g = gate
        let decision = g.decide(transcript: transcript, now: now())
        gate = g
        return decision
    }

    /// The person tapped "Back on the record".
    func resume() { var g = gate; g.end(); gate = g }
}
