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

    var wallLabel: String { DemoClock.format(wallStart) }
}
