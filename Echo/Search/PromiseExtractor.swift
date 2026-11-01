import Foundation

/// Something someone said they would do ("I will send you the spec by Wednesday"), or was reminded to do.
struct Promise: Identifiable, Equatable {
    enum Kind { case commitment, reminder }

    let id: String
    let chunkID: String
    let kind: Kind
    let timeLabel: String
    let wallStart: Double
    /// The clause from the cue onward ("I will send you the API specification by Wednesday noon").
    let sentence: String
    let toWhom: String?
    let due: String?
    /// What was said just before, which usually says who it was said to.
    let context: String?
}

/// Finds commitments in the day's transcripts, entirely on the phone with plain rules (no model).
/// Deliberately stricter than the cloud planner's cue list: only first-person "I will…" style statements and
/// explicit reminders, so "I still need the spec" is not listed as a promise.
enum PromiseExtractor {
    private static let commitmentCue = try! NSRegularExpression(
        pattern: #"\bi will\b|\bi['’]ll\b|\bi promise\b|\bi am going to\b|\bi['’]m going to\b"#, options: .caseInsensitive)
    private static let reminderCue = try! NSRegularExpression(
        pattern: #"\bremember to\b|\bdon['’]?t forget\b"#, options: .caseInsensitive)

    private static let days = "monday|tuesday|wednesday|thursday|friday|saturday|sunday"
    private static let months = "january|february|march|april|may|june|july|august|september|october|november|december"
    /// Leftmost match wins, so "by Wednesday noon" beats "Wednesday".
    private static let duePattern = try! NSRegularExpression(
        pattern: "(?:by |before |on |this |next )?(?:\(days))(?: (?:morning|afternoon|evening|noon|night))?"
            + "|tomorrow(?: (?:morning|afternoon|evening|night))?(?: first thing)?"
            + "|tonight|this (?:morning|afternoon|evening|weekend)"
            + "|(?:by |before |on )?(?:\(months)) \\d{1,2}",
        options: .caseInsensitive)

    /// Conversations are far shorter than this; a longer gap means the previous line is unrelated.
    private static let contextGap = 60.0

    /// `userName` is the profile name: a commitment is never labelled as made "to" the user themselves.
    static func extract(from chunks: [ChunkRecord], userName: String = "") -> [Promise] {
        let stored = chunks
            .filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }
            .sorted { $0.wallStart < $1.wallStart }
        var out: [Promise] = []
        for (i, chunk) in stored.enumerated() {
            let previous = i > 0 && chunk.wallStart - stored[i - 1].wallStart <= contextGap ? stored[i - 1] : nil
            for (n, sentence) in AnswerExtractor.split(chunk.transcript ?? "").enumerated() {
                guard let (kind, start) = firstCue(in: sentence) else { continue }
                let clause = polish(String(sentence[start...]))
                out.append(Promise(
                    id: "\(chunk.id)#\(n)", chunkID: chunk.id, kind: kind,
                    timeLabel: chunk.wallLabel, wallStart: chunk.wallStart, sentence: clause,
                    toWhom: kind == .commitment ? recipient(previous: previous?.transcript).flatMap { ProfileLogic.isSamePerson($0, as: userName) ? nil : $0 } : nil,
                    due: due(in: clause), context: previous?.transcript))
            }
        }
        return out
    }

    private static func firstCue(in sentence: String) -> (Promise.Kind, String.Index)? {
        let full = NSRange(sentence.startIndex..., in: sentence)
        let found: [(Promise.Kind, String.Index)] = [(Promise.Kind.commitment, commitmentCue), (.reminder, reminderCue)].compactMap { kind, regex in
            regex.firstMatch(in: sentence, range: full).flatMap { Range($0.range, in: sentence) }.map { (kind, $0.lowerBound) }
        }
        return found.min { $0.1 < $1.1 }
    }

    /// The person addressed just before the promise ("That sounds amazing Priya…" then "I will text you the link"),
    /// ignoring titled names ("Doctor Patel" is usually the subject, not the listener). Names inside the promise
    /// itself are not used: "I will call Grandma" is not said to Grandma. Often nil, because speakers are not
    /// identified; a wrong name is worse than none.
    private static func recipient(previous: String?) -> String? {
        guard let previous else { return nil }
        return TextNormalizer.personNames(in: previous).first { !$0.titled }?.name
    }

    static func due(in text: String) -> String? {
        guard let match = duePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let phrase = String(text[range])
        return phrase.prefix(1).uppercased() + phrase.dropFirst()
    }

    private static func polish(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.prefix(1).uppercased() + t.dropFirst()
        if let last = t.last, !".!?".contains(last) { t += "." }
        return t
    }
}
