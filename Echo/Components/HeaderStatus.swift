import Foundation

/// What the glanceable indicators in the top bar say. Plain values, so the wording and the states can be tested.
enum HeaderStatus {
    enum Tint: Equatable { case teal, amber, violet }

    struct Indicator: Equatable {
        let symbol: String
        let label: String
        let tint: Tint
    }

    /// Is the watch there, and is it listening?
    static func watch(reachable: Bool, listening: Bool) -> Indicator {
        if listening { return Indicator(symbol: "waveform", label: "Watch is listening", tint: .teal) }
        // Connected but the microphone is off: the same sound bars, standing still (they only move while it listens).
        if reachable { return Indicator(symbol: "waveform", label: "Watch connected, not listening", tint: .teal) }
        return Indicator(symbol: "applewatch.slash", label: "Watch not reachable", tint: .amber)
    }

    /// Can broad questions use Muse, and do you approve each one?
    static func cloud(enabled: Bool, reviewing: Bool) -> Indicator {
        guard enabled else { return Indicator(symbol: "cloud.slash", label: "Cloud is off. Nothing is sent", tint: .amber) }
        return Indicator(symbol: "cloud.fill", label: reviewing ? "Cloud is on. You approve each request" : "Cloud is on for broad questions", tint: .violet)
    }

    static let lock = Indicator(symbol: "lock.fill", label: "Everything stays on this phone", tint: .teal)
}
