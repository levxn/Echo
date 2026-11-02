import Foundation

// The Moments tab speaks plain language. Everything it says is decided here, away from SwiftUI, so it can be tested.

extension Format {
    /// 233 -> "3 min 53 s", 45 -> "45 s", 240 -> "4 min".
    static func minutesSeconds(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let (m, r) = (s / 60, s % 60)
        if m == 0 { return "\(r) s" }
        return r == 0 ? "\(m) min" : "\(m) min \(r) s"
    }
}

private func plural(_ n: Int, _ one: String, _ many: String? = nil) -> String {
    n == 1 ? "1 \(one)" : "\(n) \(many ?? one + "s")"
}

// MARK: - Status banner

/// What the banner at the top of Moments says: is the watch listening, has the phone caught up?
struct CaptureStatus: Equatable {
    enum Kind { case waitingForWatch, watchReady, listening, catchingUp, caughtUp }
    enum Phase { case waiting, running, finished }

    var kind: Kind
    var title: String
    var detail: String
    var footnote: String?
    /// 0...1 while something is in progress; nil when there is nothing to measure.
    var progress: Double?
    var symbol: String

    static func make(phase: Phase, reachable: Bool, arrived: Int, pending: Int, stored: Int, ignored: Int,
                     conversations: Int, keptSeconds: Double, fraction: Double, expected: Int = 0) -> CaptureStatus {
        if arrived == 0 && phase == .waiting {
            return reachable
                ? CaptureStatus(kind: .watchReady, title: "Watch connected", detail: "Tap Start day on your watch and Echo starts listening.",
                                footnote: nil, progress: nil, symbol: "applewatch.radiowaves.left.and.right")
                : CaptureStatus(kind: .waitingForWatch, title: "Waiting for your watch", detail: "Open Echo on your watch to begin.",
                                footnote: nil, progress: nil, symbol: "applewatch.slash")
        }
        switch phase {
        case .waiting, .running:
            let heard = max(0, arrived - ignored)
            return CaptureStatus(kind: .listening, title: "Listening",
                                 detail: "\(plural(heard, "moment")) so far",
                                 footnote: "Only speech is kept. It stays on this phone.", progress: fraction, symbol: "waveform")
        case .finished:
            // The watch can finish before its last snippets have arrived, so count those still on the way too.
            let total = max(arrived, expected)
            if pending > 0 || arrived < expected {
                let done = max(0, arrived - pending)
                return CaptureStatus(kind: .catchingUp, title: "Catching up",
                                     detail: "Understanding \(done) of \(total)",
                                     footnote: "Checked and transcribed on this phone.",
                                     progress: total > 0 ? Double(done) / Double(total) : nil, symbol: "arrow.triangle.2.circlepath")
            }
            return CaptureStatus(kind: .caughtUp, title: "Caught up",
                                 detail: "\(plural(stored, "moment")) from \(plural(conversations, "conversation")) · \(Format.minutesSeconds(keptSeconds)) kept",
                                 footnote: "Everything stays on this phone.", progress: nil, symbol: "checkmark.circle.fill")
        }
    }
}

extension PipelineModel {
    /// The banner for the current state of the day.
    func captureStatus(conversations: Int) -> CaptureStatus {
        CaptureStatus.make(
            phase: { switch session { case .waiting: .waiting; case .running: .running; case .finished: .finished } }(),
            reachable: watchReachable, arrived: arrivedCount, pending: chunks.filter { [.received, .vad, .asr].contains($0.status) }.count,
            stored: storedCount, ignored: droppedCount, conversations: conversations,
            keptSeconds: phoneConfirmedSeconds, fraction: sessionFraction, expected: expectedChunks)
    }
}

// MARK: - The feed

/// One line in the feed: a transcript, or a moment that is still being understood.
struct MomentItem: Identifiable, Equatable {
    let id: String             // the moment's id
    let timeLabel: String
    let text: String?          // nil while it is still being understood
    var duration: Double = 0   // seconds of speech, for the ribbon
    /// Still moving through the phone: it can't be played or deleted yet.
    var inFlight = false
    /// Whose voice it is, when the phone could tell.
    var speakerId = ""
    var isWorking: Bool { text == nil }
}

struct MomentGroup: Identifiable, Equatable {
    let id: Int                // the conversation's start, in seconds: stable while the day grows
    let title: String
    let startLabel: String
    let items: [MomentItem]
    var count: Int { items.count }
}

/// What the feed shows: conversations of understood moments, the moments still being worked on, and counts of
/// what was left out (noise the phone ignored, anything that failed).
struct MomentsLayout: Equatable {
    var groups: [MomentGroup]
    var working: [MomentItem]
    var ignored: Int
    var failed: Int

    static func make(from chunks: [ChunkRecord]) -> MomentsLayout {
        let groups = EpisodeBuilder.build(from: chunks).map { episode in
            MomentGroup(id: Int(episode.start), title: episode.title, startLabel: episode.startLabel,
                        items: episode.chunks.map { MomentItem(id: $0.id, timeLabel: $0.wallLabel, text: $0.transcript, duration: $0.duration, speakerId: $0.speakerId) })
        }
        let working = chunks
            .filter { [.received, .vad, .asr].contains($0.status) }
            .sorted { $0.wallStart < $1.wallStart }
            .map { MomentItem(id: $0.id, timeLabel: $0.wallLabel, text: $0.status == .asr ? $0.transcript : nil,
                              duration: $0.duration, inFlight: true) }
        return MomentsLayout(groups: groups, working: working,
                             ignored: chunks.filter { $0.status == .dropped }.count,
                             failed: chunks.filter { $0.status == .failed }.count)
    }

    /// Which groups are open. While the day is still arriving the newest one is open so new lines are seen;
    /// once it has settled everything is closed so the page is short.
    static func openGroups(_ layout: MomentsLayout, settled: Bool, mode: String?) -> Set<Int> {
        switch mode {
        case "all": return Set(layout.groups.map(\.id))
        case "none": return []
        case "latest": return layout.groups.last.map { [$0.id] } ?? []
        default: return settled ? [] : (layout.groups.last.map { [$0.id] } ?? [])
        }
    }
}

// MARK: - The ribbon

/// Geometry for the "when it listened" ribbon: one block per conversation, one bar per moment.
enum Ribbon {
    static let maxBars = 24
    static let minHeight = 0.25
    /// Every block keeps at least this share of the width so a short conversation is still tappable.
    static let minShare = 0.14

    /// Bar heights in `minHeight...1`, from each moment's length. Long conversations are sampled down.
    static func bars(durations: [Double]) -> [Double] {
        guard !durations.isEmpty else { return [] }
        var sampled = durations
        if durations.count > maxBars {
            sampled = (0..<maxBars).map { durations[$0 * durations.count / maxBars] }
        }
        let longest = sampled.max() ?? 0
        guard longest > 0 else { return sampled.map { _ in 0.5 } }
        return sampled.map { minHeight + (1 - minHeight) * max(0, $0) / longest }
    }

    /// Width shares that add up to 1: roughly the square root of each conversation's moment count, never
    /// below `minShare`.
    static func shares(counts: [Int]) -> [Double] {
        guard !counts.isEmpty else { return [] }
        let floor = min(minShare, 1 / Double(counts.count))
        let raw = counts.map { sqrt(Double(max(1, $0))) }
        let total = raw.reduce(0, +)
        var shares = raw.map { max(floor, $0 / total) }
        let sum = shares.reduce(0, +)
        shares = shares.map { $0 / sum }
        return shares
    }
}

// MARK: - Behind the scenes

/// The technical story in plain sentences, for the collapsed "Behind the scenes" section.
enum BehindTheScenes {
    static func lines(arrived: Int, stored: Int, ignored: Int, failed: Int,
                      recorded: Double, kept: Double, confirmed: Double) -> [String] {
        var out = ["\(plural(arrived, "short snippet")) arrived from the watch."]
        var verdict = "\(stored) \(stored == 1 ? "was" : "were") speech and \(stored == 1 ? "is" : "are") kept; \(ignored) \(ignored == 1 ? "was" : "were") noise and ignored."
        if failed > 0 { verdict += " \(plural(failed, "snippet")) couldn't be processed." }
        out.append(verdict)
        if recorded > 0 {
            out.append("The watch kept \(Format.minutesSeconds(kept)) of the \(Format.minutesSeconds(recorded)) it heard, and the phone confirmed \(Format.minutesSeconds(confirmed)) as speech.")
        }
        out.append("All of it was checked and transcribed on this phone.")
        return out
    }
}
