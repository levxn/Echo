import Foundation

/// Something that was decided or agreed ("We decided to go with the second vendor").
struct Decision: Identifiable, Equatable {
    let id: String
    let chunkID: String
    let dayId: String
    /// When it was said, with the day if it wasn't today.
    let timeLabel: String
    let sentence: String
    let speakerId: String
    /// What was said just before, usually the question being settled.
    let context: String?
}

/// Finds decisions in the transcripts, on the phone with plain rules (no model).
enum DecisionExtractor {
    private static let cue = try! NSRegularExpression(
        pattern: #"\bwe(?:'ve| have| had)? decided\b|\bi(?:'ve| have| had)? decided\b|\bwe(?:'ve| have)? agreed\b|\blet['’]?s go with\b|\bwe['’]ll go with\b|\bwe(?:['’]re| are) going with\b|\bthe (?:final )?decision is\b|\bfinal decision\b"#,
        options: .caseInsensitive)

    /// Oldest first; each moment is looked at on its own day.
    static func extract(from chunks: [ChunkRecord], now: Date = Date()) -> [Decision] {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }
            .sorted { ($0.dayId, $0.wallStart) < ($1.dayId, $1.wallStart) }
        var out: [Decision] = []
        for (i, chunk) in stored.enumerated() {
            let previous = i > 0 && stored[i - 1].dayId == chunk.dayId && chunk.wallStart - stored[i - 1].wallStart <= 60 ? stored[i - 1] : nil
            for (n, sentence) in AnswerExtractor.split(chunk.transcript ?? "").enumerated() {
                guard cue.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)) != nil else { continue }
                var s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                s = s.prefix(1).uppercased() + s.dropFirst()
                if let last = s.last, !".!?".contains(last) { s += "." }
                out.append(Decision(id: "\(chunk.id)#d\(n)", chunkID: chunk.id, dayId: chunk.dayId, timeLabel: chunk.stamp(now: now),
                                    sentence: s, speakerId: chunk.speakerId, context: previous?.transcript))
            }
        }
        return out
    }
}
