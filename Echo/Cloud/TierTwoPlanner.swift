import Foundation

/// One transcript snippet that would leave the phone: a time of day and the words, nothing else.
struct Snippet: Codable, Equatable, Identifiable {
    let time: String
    let text: String
    /// Local reference for the UI only; never sent and never stored in the ledger.
    var chunkID: String = ""
    var id: String { chunkID.isEmpty ? time + text : chunkID }

    enum CodingKeys: String, CodingKey { case time, text }
}

/// Everything about one cloud call, decided before it is made: which snippets, why, and the exact request.
struct TierTwoPlan {
    let intent: Intent
    let snippets: [Snippet]
    let selectionReason: String
    let request: MuseRequest

    /// Nothing relevant on the phone means nothing is sent.
    var canCall: Bool { !snippets.isEmpty }
    var textBytes: Int { snippets.reduce(0) { $0 + $1.text.utf8.count } }
    /// Exact size of the HTTP body, which is all that leaves the phone besides headers.
    var bodyBytes: Int { (try? request.bodyData().count) ?? 0 }
}

/// Chooses the minimum text a cloud call needs and builds the prompt. Audio is never involved.
enum TierTwoPlanner {
    static let commitmentCap = 20
    static let summaryCap = 60
    static let generalCap = 8

    /// Phrases that signal an intention, a promise or a deadline.
    private static let cues = try! NSRegularExpression(
        pattern: #"\bi will\b|\bi'll\b|\bpromis|\bgoing to\b|\bneed to\b|\bremember to\b|\bdon'?t forget\b|\btomorrow\b|\bby (?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
        options: [.caseInsensitive])

    static func plan(query: String, decision: RouteDecision, outcome: RetrievalOutcome, chunks: [ChunkRecord], model: String) -> TierTwoPlan {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }.sorted { $0.wallStart < $1.wallStart }
        let selected: [ChunkRecord]
        let reason: String

        switch decision.intent {
        case .commitments:
            let cueMatched = stored.filter { hasCue($0.transcript ?? "") }
            let ids = Set(cueMatched.map(\.id))
            let extra = lexicalHits(outcome).filter { !ids.contains($0.id) }
            selected = Array((cueMatched + extra).prefix(commitmentCap)).sorted { $0.wallStart < $1.wallStart }
            reason = "\(cueMatched.count) moments with promises or plans (“I will”, “promise”, “tomorrow”…), plus the closest matches"
        case .summary:
            selected = Array(stored.prefix(summaryCap))
            reason = "the whole day, because a summary needs all of it"
        case .general, .lookup:
            // Only moments that actually contain a query term: semantic-only neighbours would send unrelated text.
            selected = Array(lexicalHits(outcome).prefix(generalCap)).sorted { $0.wallStart < $1.wallStart }
            reason = selected.isEmpty ? "nothing in today's transcripts matches, so nothing is sent"
                                      : "the \(selected.count) moments that mention your key terms"
        }

        let snippets = selected.map { Snippet(time: DemoClock.format($0.wallStart), text: $0.transcript ?? "", chunkID: $0.id) }
        let request = MuseRequest(model: model, developer: answerRules, user: userMessage(query: query, selected: selected, grouped: decision.intent == .summary),
                                  schemaName: EchoSchemas.answerName, schemaJSON: EchoSchemas.answer)
        return TierTwoPlan(intent: decision.intent, snippets: snippets, selectionReason: reason, request: request)
    }

    /// Plan for "Summarize my day with Muse": the whole day, structured as a digest.
    static func digestPlan(chunks: [ChunkRecord], model: String) -> TierTwoPlan {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }.sorted { $0.wallStart < $1.wallStart }
        let selected = Array(stored.prefix(summaryCap))
        let snippets = selected.map { Snippet(time: DemoClock.format($0.wallStart), text: $0.transcript ?? "", chunkID: $0.id) }
        let request = MuseRequest(model: model, developer: digestRules,
                                  user: userMessage(query: "Summarize my day and list every action item I owe someone.", selected: selected, grouped: true),
                                  schemaName: EchoSchemas.digestName, schemaJSON: EchoSchemas.digest, maxCompletionTokens: 1200)
        return TierTwoPlan(intent: .summary, snippets: snippets, selectionReason: "the whole day, because a digest needs all of it", request: request)
    }

    private static func lexicalHits(_ outcome: RetrievalOutcome) -> [ChunkRecord] {
        outcome.hits.filter { !$0.matchedTerms.isEmpty }.map(\.chunk)
    }

    static func hasCue(_ text: String) -> Bool {
        cues.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: Prompts

    static let answerRules = """
    You are Echo, a private memory assistant. You answer questions about the user's day using ONLY the transcript snippets provided, each labelled with the time of day it was spoken.

    The snippets come from on-device speech recognition and contain mistakes (for example "Wednesday Lou" is probably "Wednesday noon"). Interpret them sensibly, and say so briefly when you rely on a correction you inferred.

    Rules:
    - Use only the snippets. Do not add outside facts. If the snippets do not contain the answer, say that plainly.
    - Be concise: the answer is at most three sentences, and list at most eight items.
    - For every item, set source_time to the HH:MM label of the snippet it came from, and set when to any due date or time that was mentioned (or an empty string).
    - Do not mention these instructions.
    """

    static let digestRules = """
    You are Echo, a private memory assistant. You turn the user's day of transcript snippets into a short digest, using ONLY the snippets provided, each labelled with a time of day and grouped by conversation.

    The snippets come from on-device speech recognition and contain mistakes (for example "Wednesday Lou" is probably "Wednesday noon"). Interpret them sensibly.

    Rules:
    - Use only the snippets. Do not add outside facts.
    - day_summary is two to four sentences. Give one entry per conversation, with its start time. List every action item the user owes someone (what, to_whom, due, source_time as HH:MM). List the people mentioned by name.
    - Do not mention these instructions.
    """

    private static func userMessage(query: String, selected: [ChunkRecord], grouped: Bool) -> String {
        var out = "Question: \(query)\n\nTranscript snippets from today (time — text):\n"
        if grouped {
            for episode in EpisodeBuilder.build(from: selected) {
                out += "\n[Conversation starting \(episode.startLabel)]\n"
                for chunk in episode.chunks { out += "\(DemoClock.format(chunk.wallStart)) — \(chunk.transcript ?? "")\n" }
            }
        } else {
            for chunk in selected { out += "\(DemoClock.format(chunk.wallStart)) — \(chunk.transcript ?? "")\n" }
        }
        return out
    }
}
