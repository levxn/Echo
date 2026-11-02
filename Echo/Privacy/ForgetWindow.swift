import Foundation

/// "Forget the last few minutes": which moments that covers.
nonisolated enum ForgetWindow {
    static let options = [5, 10, 30, 60]

    /// The moments heard in the last `minutes` of what was captured: counted back from the end of the newest moment, on its
    /// day. (Counting from the newest moment rather than the clock works the same whether the day is arriving live or is
    /// being caught up.) Every moment counts, whatever stage it is at, so nothing half-processed is left behind.
    static func chunks(in all: [ChunkRecord], minutes: Int) -> [ChunkRecord] {
        guard minutes > 0, let newest = all.max(by: { ($0.dayId, $0.wallStart + $0.duration) < ($1.dayId, $1.wallStart + $1.duration) }) else { return [] }
        let cutoff = newest.wallStart + newest.duration - Double(minutes) * 60
        return all.filter { $0.isOn(newest.dayId) && $0.wallStart + $0.duration > cutoff }
    }

    static func title(minutes: Int) -> String { minutes == 60 ? "hour" : "\(minutes) minutes" }
}

/// "Off the record": say it and Echo stops keeping anything until you say "back on the record" (or ten minutes pass).
/// While it is off, what is heard is understood only long enough to listen for "back on the record", then thrown away:
/// never stored, never searchable, never sent.
nonisolated struct PrivacyGate: Equatable {
    static let window: TimeInterval = 10 * 60

    enum Decision: Equatable {
        case keep
        /// The command itself ("this is off the record"): not kept either.
        case dropCommand
        /// Said while off the record.
        case dropPrivate
    }

    private(set) var offUntil: Date?

    func isPrivate(now: Date = Date()) -> Bool { offUntil.map { $0 > now } ?? false }

    static func isOffCommand(_ text: String) -> Bool { normalized(text).contains("off the record") }
    static func isBackOnCommand(_ text: String) -> Bool {
        let t = normalized(text)
        return t.contains("back on the record") || t.contains("on the record again") || t.contains("we are on the record")
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: { !$0.isLetter && !$0.isWhitespace }).joined(separator: " ")
    }

    /// What to do with something that was just understood.
    mutating func decide(transcript: String?, now: Date = Date()) -> Decision {
        let text = transcript ?? ""
        if Self.isBackOnCommand(text) { offUntil = nil; return .dropCommand }
        if Self.isOffCommand(text) { offUntil = now.addingTimeInterval(Self.window); return .dropCommand }
        return isPrivate(now: now) ? .dropPrivate : .keep
    }

    mutating func end() { offUntil = nil }
}
