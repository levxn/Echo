import Foundation

enum ChunkStatus: String, Sendable {
    case received   // reassembled from the watch
    case vad        // stage-2 voice check done
    case dropped    // stage 2 judged it non-speech
    case asr        // transcribed
    case stored     // fully processed and indexed
    case failed
}

struct ChunkRecord: Identifiable, Sendable, Equatable {
    let id: String
    let index: Int
    let wallStart: Double        // seconds since midnight (demo clock)
    let fileOffset: Double
    let duration: Double
    let peakDb: Double
    let meanDb: Double
    let audioFile: String        // m4a file name inside the chunks directory
    var status: ChunkStatus
    var speechConfidence: Double?
    var confirmedSeconds: Double // audio kept after stage 2 (0 if dropped)
    var transcript: String?
    /// The calendar day this was said on ("2026-11-02"); empty for a moment stored before days existed.
    var dayId: String = ""
    /// Whose voice it is ("" until the phone has told voices apart). See `SpeakerBook`.
    var speakerId: String = ""

    var wallLabel: String { DemoClock.format(wallStart) }

    /// When it was said, with the day if it wasn't today: "12:30", or "Mon 12:30".
    func stamp(now: Date = Date()) -> String {
        dayId.isEmpty || dayId == DayID.today(now: now) ? wallLabel : "\(DayID.shortLabel(dayId, now: now)) \(wallLabel)"
    }

    /// Is this from `day`? Moments from before days existed count as belonging to every day.
    func isOn(_ day: String) -> Bool { dayId.isEmpty || dayId == day }
}
