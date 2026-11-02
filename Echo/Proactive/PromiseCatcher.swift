import Foundation

/// Decides which freshly heard promise is worth interrupting for: a commitment, not too soon after the last one, and only a few
/// per session, so a chatty day doesn't turn into a stream of buzzes. Pure.
nonisolated struct PromiseCatcher: Equatable {
    static let minGap: TimeInterval = 20
    static let maxPerSession = 3

    private(set) var seen: Set<String> = []
    private(set) var lastCaught: Date?
    private(set) var count = 0

    /// The promise to surface from what was just heard in `chunkID`, if any. Everything in that moment is marked seen either way.
    mutating func next(from promises: [Promise], chunkID: String, onlyVoice: String? = nil, now: Date = Date()) -> Promise? {
        let fresh = promises.filter { $0.chunkID == chunkID && !seen.contains($0.id) }
        seen.formUnion(fresh.map(\.id))
        guard let pick = fresh.first(where: { $0.kind == .commitment && (onlyVoice == nil || $0.speakerId == onlyVoice) }) else { return nil }
        if count >= Self.maxPerSession { return nil }
        if let last = lastCaught, now.timeIntervalSince(last) < Self.minGap { return nil }
        lastCaught = now
        count += 1
        return pick
    }

    /// A new capture session starts the allowance again.
    mutating func newSession() { self = PromiseCatcher() }
}

/// Watches what the pipeline stores and surfaces promises as they are said (to the watch, or as a notification).
@MainActor
final class PromiseWatcher {
    private let model: PipelineModel
    private(set) var catcher = PromiseCatcher()
    private var sessionDay: String?
    /// Whether to do this at all (the person's setting).
    var isEnabled: () -> Bool = { true }
    /// The voice that counts as the person's own, once they have said which it is.
    var myVoice: () -> String? = { nil }
    var onCaught: ((Promise) -> Void)?

    init(model: PipelineModel) { self.model = model }

    /// Call after a moment has been stored.
    func chunkStored(_ chunk: ChunkRecord) {
        guard isEnabled(), chunk.status == .stored, chunk.dayId.isEmpty || chunk.dayId == DayID.today(now: model.now()) else { return }
        if sessionDay != chunk.dayId { catcher.newSession(); sessionDay = chunk.dayId }
        let promises = PromiseExtractor.extract(from: model.chunks(on: chunk.dayId))
        if let caught = catcher.next(from: promises, chunkID: chunk.id, onlyVoice: myVoice(), now: Date()) { onCaught?(caught) }
    }
}
