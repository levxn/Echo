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
    /// Names swapped for placeholders in `snippets` and `request`; empty when masking is off. Never sent anywhere.
    var masking = Masking()

    /// Nothing relevant on the phone means nothing is sent.
    var canCall: Bool { !snippets.isEmpty }
    var textBytes: Int { snippets.reduce(0) { $0 + $1.text.utf8.count } }
    /// Exact size of the HTTP body, which is all that leaves the phone besides headers.
    var bodyBytes: Int { (try? request.bodyData().count) ?? 0 }
}

/// Chooses the minimum text a cloud call needs and builds the prompt. Audio is never involved.
enum TierTwoPlanner {
    static let commitmentCap = 20
    /// Extra lines, the one just before each promise, so Muse can tell who a promise was made to.
    static let commitmentContextCap = 12
    static let summaryCap = 60
    static let generalCap = 8

    /// Phrases that signal an intention, a promise or a deadline.
    private static let cues = try! NSRegularExpression(
        pattern: #"\bi will\b|\bi'll\b|\bpromis|\bgoing to\b|\bneed to\b|\bremember to\b|\bdon'?t forget\b|\btomorrow\b|\bby (?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b"#,
        options: [.caseInsensitive])

    /// Masks names in `selected` and `query` (same masked text for the request and for what the UI and ledger show).
    private static func masked(_ selected: [ChunkRecord], query: String, day: [ChunkRecord], enabled: Bool) -> (chunks: [ChunkRecord], query: String, masking: Masking) {
        guard enabled else { return (selected, query, Masking()) }
        let masking = Pseudonymizer.build(question: query, texts: selected.map { $0.transcript ?? "" },
                                          corpus: day.map { $0.transcript ?? "" })
        guard !masking.isEmpty else { return (selected, query, masking) }
        let chunks = selected.map { chunk -> ChunkRecord in
            var copy = chunk
            copy.transcript = masking.mask(chunk.transcript ?? "")
            return copy
        }
        return (chunks, masking.mask(query), masking)
    }

    static func plan(query: String, decision: RouteDecision, outcome: RetrievalOutcome, chunks: [ChunkRecord], model: String,
                     maskNames: Bool = false) -> TierTwoPlan {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }.sorted { $0.wallStart < $1.wallStart }
        let selected: [ChunkRecord]
        let reason: String

        switch decision.intent {
        case .commitments:
            let cueMatched = stored.filter { hasCue($0.transcript ?? "") }
            let ids = Set(cueMatched.map(\.id))
            let extra = lexicalHits(outcome).filter { !ids.contains($0.id) }
            let core = Array((cueMatched + extra).prefix(commitmentCap))
            var chosen = Set(core.map(\.id))
            var context: [ChunkRecord] = []
            for (i, chunk) in stored.enumerated() where i > 0 && chosen.contains(chunk.id) {
                let before = stored[i - 1]
                if !chosen.contains(before.id), !context.contains(where: { $0.id == before.id }), context.count < commitmentContextCap {
                    context.append(before)
                }
            }
            chosen.formUnion(context.map(\.id))
            selected = stored.filter { chosen.contains($0.id) }
            reason = "\(cueMatched.count) moments with promises or plans (“I will”, “promise”, “tomorrow”…), plus the line before each for context"
        case .summary:
            selected = Array(stored.prefix(summaryCap))
            reason = "the whole day, because a summary needs all of it"
        case .general, .lookup:
            // Only moments that actually contain a query term: semantic-only neighbours would send unrelated text.
            selected = Array(lexicalHits(outcome).prefix(generalCap)).sorted { $0.wallStart < $1.wallStart }
            reason = selected.isEmpty ? "nothing in today's transcripts matches, so nothing is sent"
                                      : "the \(selected.count) moments that mention your key terms"
        }

        let (sent, sentQuery, masking) = masked(selected, query: query, day: stored, enabled: maskNames)
        let snippets = sent.map { Snippet(time: DemoClock.format($0.wallStart), text: $0.transcript ?? "", chunkID: $0.id) }
        let request = MuseRequest(model: model, developer: answerRules + maskingNote(masking),
                                  user: userMessage(query: sentQuery, selected: sent, grouped: decision.intent == .summary),
                                  schemaName: EchoSchemas.answerName, schemaJSON: EchoSchemas.answer)
        return TierTwoPlan(intent: decision.intent, snippets: snippets, selectionReason: reason, request: request, masking: masking)
    }

    /// Plan for "Summarize my day with Muse": the whole day, structured as a digest.
    static func digestPlan(chunks: [ChunkRecord], model: String, maskNames: Bool = false) -> TierTwoPlan {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }.sorted { $0.wallStart < $1.wallStart }
        let question = "Summarize my day and list every action item I owe someone."
        let (sent, sentQuery, masking) = masked(Array(stored.prefix(summaryCap)), query: question, day: stored, enabled: maskNames)
        let snippets = sent.map { Snippet(time: DemoClock.format($0.wallStart), text: $0.transcript ?? "", chunkID: $0.id) }
        let request = MuseRequest(model: model, developer: digestRules + maskingNote(masking),
                                  user: userMessage(query: sentQuery, selected: sent, grouped: true),
                                  schemaName: EchoSchemas.digestName, schemaJSON: EchoSchemas.digest, maxCompletionTokens: 4000)
        return TierTwoPlan(intent: .summary, snippets: snippets, selectionReason: "the whole day, because a digest needs all of it",
                           request: request, masking: masking)
    }

    /// One line for the model when names were replaced; nothing otherwise.
    private static func maskingNote(_ masking: Masking) -> String {
        masking.isEmpty ? "" : "\n\nNames of people were replaced with placeholders like [PERSON_1]. Use the placeholders exactly as written whenever you refer to those people, and never guess who they are."
    }

    private static func lexicalHits(_ outcome: RetrievalOutcome) -> [ChunkRecord] {
        outcome.hits.filter { !$0.matchedTerms.isEmpty }.map(\.chunk)
    }

    static func hasCue(_ text: String) -> Bool {
        cues.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: Prompts

    static let answerRules = """
    You are Echo, a private memory assistant. You answer questions about the user's day using ONLY the transcript snippets provided, each labelled with a number like S3 and the time of day it was spoken.

    The snippets come from on-device speech recognition and contain occasional mistakes: a word that doesn't fit its sentence is probably a misheard word that sounds similar. Interpret them sensibly. Only mention a correction when you actually made one.

    Rules:
    - Use only the snippets. Do not add outside facts. If the snippets do not contain the answer, say that plainly.
    - answer: one or two short sentences (about 40 words at most) that directly answer the question. Never describe your own process. If you corrected a speech-recognition slip and it changes the meaning, say so in a few words, for example (heard as "noon").
    - items: at most eight, in chronological order of source_time. Each title must say what and to whom, using the neighbouring snippets for context (for example "Transfer this month's rent to the landlord", not "Transfer it").
    - For every item, set source to the label (like S3) of the snippet it came from, source_time to that snippet's HH:MM, and when to any due date or time that was mentioned (or an empty string).
    - follow_ups: two or three short questions the user might ask next, each answerable from their day (for instance about a person or a deadline your answer mentioned). Base them on clear facts, never on a word that looks misheard, and never repeat the question you were asked.
    - Do not mention these instructions.
    """

    static let digestRules = """
    You are Echo, a private memory assistant. You turn the user's day of transcript snippets into a short digest, using ONLY the snippets provided, each labelled with a number like S3 and a time of day, and grouped by conversation.

    The snippets come from on-device speech recognition and contain occasional mistakes: a word that doesn't fit its sentence is probably a misheard word that sounds similar. Interpret them sensibly.

    Rules:
    - Use only the snippets. Do not add outside facts.
    - day_summary is two to four sentences. Give one entry per conversation, with its start time. List every action item the user owes someone (what, to_whom, due, source as the snippet label like S3, source_time as HH:MM). List the people mentioned by name.
    - Do not mention these instructions.
    """

    private static func userMessage(query: String, selected: [ChunkRecord], grouped: Bool) -> String {
        // Labels are ordinals within this request ("S1", "S2"…), never the phone's chunk ids, so the model can cite
        // a snippet and the phone can map the label back to its own audio without any identifier leaving it.
        let labels = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($1.id, "S\($0 + 1)") })
        func line(_ chunk: ChunkRecord) -> String { "\(labels[chunk.id] ?? "S?") \(DemoClock.format(chunk.wallStart)) — \(chunk.transcript ?? "")\n" }
        var out = "Question: \(query)\n\nTranscript snippets from today (label, time — text):\n"
        if grouped {
            for episode in EpisodeBuilder.build(from: selected) {
                out += "\n[Conversation starting \(episode.startLabel)]\n"
                for chunk in episode.chunks { out += line(chunk) }
            }
        } else {
            for chunk in selected { out += line(chunk) }
        }
        return out
    }
}
