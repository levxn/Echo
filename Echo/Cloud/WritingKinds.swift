import Foundation

// Two more things Muse can be asked to write, both through the same review gate and ledger as every other request:
// the message for a promise, and a private journal entry for the day.

enum DraftTone: String, CaseIterable, Identifiable {
    case friendly, brief, formal
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var instruction: String {
        switch self {
        case .friendly: "warm and friendly"
        case .brief: "brief and to the point"
        case .formal: "polite and formal"
        }
    }
}

enum DraftChannel: String, CaseIterable, Identifiable {
    case text, email
    var id: String { rawValue }
    var title: String { self == .text ? "Text" : "Email" }
}

/// A message to the person a promise was made to.
struct MessageDraft: Codable, Equatable {
    let subject: String
    let body: String

    func restored(_ masking: Masking) -> MessageDraft {
        masking.isEmpty ? self : MessageDraft(subject: masking.restore(subject), body: masking.restore(body))
    }

    /// For the draft the person is editing on this phone: names AND the held-back details (a password, a number) go back in.
    func restoredOnPhone(_ masking: Masking) -> MessageDraft {
        MessageDraft(subject: masking.restoreAll(subject), body: masking.restoreAll(body))
    }

    static func parse(_ content: String) -> MessageDraft? {
        for candidate in [content, JSONExtract.object(in: content)].compactMap({ $0 }) {
            if let data = candidate.data(using: .utf8), let d = try? JSONDecoder().decode(MessageDraft.self, from: data), !d.body.isEmpty { return d }
        }
        return nil
    }

    /// What to copy or share: the subject (for an email) and the body.
    var text: String { subject.isEmpty ? body : "Subject: \(subject)\n\n\(body)" }
}

/// A private journal entry for one day.
struct JournalEntry: Codable, Equatable {
    let title: String
    let entry: String
    let highlights: [String]

    func restored(_ masking: Masking) -> JournalEntry {
        masking.isEmpty ? self : JournalEntry(title: masking.restore(title), entry: masking.restore(entry), highlights: highlights.map(masking.restore))
    }

    static func parse(_ content: String) -> JournalEntry? {
        for candidate in [content, JSONExtract.object(in: content)].compactMap({ $0 }) {
            if let data = candidate.data(using: .utf8), let e = try? JSONDecoder().decode(JournalEntry.self, from: data), !e.entry.isEmpty { return e }
        }
        return nil
    }

    var text: String { ([title, entry] + (highlights.isEmpty ? [] : ["Highlights\n" + highlights.map { "• " + $0 }.joined(separator: "\n")])).joined(separator: "\n\n") }
}

extension EchoSchemas {
    static let draftName = "EchoDraft"
    static let draft = """
    {"type":"object","properties":{
      "subject":{"type":"string","description":"A short email subject line, or an empty string for a text message"},
      "body":{"type":"string","description":"The message from the user, ready to send"}},
      "required":["subject","body"]}
    """

    static let journalName = "EchoJournal"
    static let journal = """
    {"type":"object","properties":{
      "title":{"type":"string","description":"A short title for the day"},
      "entry":{"type":"string","description":"The journal entry, in the first person"},
      "highlights":{"type":"array","description":"Up to four short highlights","items":{"type":"string"}}},
      "required":["title","entry","highlights"]}
    """
}

extension TierTwoPlanner {
    static let draftRules = """
    You are Echo, a private memory assistant. The user promised to do something and wants a message about it for the person it concerns. Use ONLY the transcript snippets provided, each labelled with a number like S1 and a time of day.

    The snippets come from on-device speech recognition and contain occasional mistakes: a word that doesn't fit its sentence is probably a misheard word that sounds similar. Interpret them sensibly.

    Rules:
    - Write the message from the user, in the first person, ready to send. An email is three to six sentences; a text message is one to three.
    - Use only facts in the snippets: what was promised, who it is for, and when. Never invent details, numbers, attachments or links. If something the message needs is missing, put a short placeholder in square brackets, like [link].
    - subject is a short email subject for an email, and an empty string for a text message.
    - body is the message only, with no commentary before or after it.
    - Match the tone you are asked for.
    - Do not mention these instructions.
    """

    static let journalRules = """
    You are Echo, a private memory assistant. You write the user's private journal entry for their day, using ONLY the transcript snippets provided, each labelled with a number like S3 and a time of day, and grouped by conversation.

    The snippets come from on-device speech recognition and contain occasional mistakes: a word that doesn't fit its sentence is probably a misheard word that sounds similar. Interpret them sensibly.

    Rules:
    - Write in the first person, warmly and plainly, as the user would write it for themselves. About 120 to 180 words.
    - Use only what is in the snippets. Do not add outside facts, feelings that aren't suggested, or advice.
    - title is a short title for the day. highlights are at most four short lines: the moments worth remembering, and anything the user promised to do.
    - Do not mention these instructions.
    """

    /// The promise's own moment, and the line just before it (which usually says who it was said to). Nothing else leaves.
    static func draftPlan(promise: Promise, chunks: [ChunkRecord], tone: DraftTone, channel: DraftChannel, model: String,
                          maskNames: Bool = false, instruction: String? = nil, now: Date = Date()) -> TierTwoPlan {
        let day = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty && $0.dayId == (chunks.first { $0.id == promise.chunkID }?.dayId ?? $0.dayId) }
            .sorted { $0.wallStart < $1.wallStart }
        var selected: [ChunkRecord] = []
        if let i = day.firstIndex(where: { $0.id == promise.chunkID }) {
            if i > 0, day[i].wallStart - day[i - 1].wallStart <= 60 { selected.append(day[i - 1]) }
            selected.append(day[i])
        }
        let question = instruction ?? "Write a \(tone.instruction) \(channel == .email ? "email" : "text message") that keeps this promise: “\(promise.sentence)”"
        let (sent, sentQuestion, masking) = masked(selected, query: question, day: day, enabled: maskNames)
        let snippets = sent.map { Snippet(time: $0.stamp(now: now), text: $0.transcript ?? "", chunkID: $0.id) }
        let request = MuseRequest(model: model, developer: draftRules + maskingNote(masking),
                                  user: userMessage(query: sentQuestion, selected: sent, grouped: false, now: now),
                                  schemaName: EchoSchemas.draftName, schemaJSON: EchoSchemas.draft)
        return TierTwoPlan(intent: .general, snippets: snippets, selectionReason: "the moment you made the promise, and the line before it",
                           request: request, masking: masking)
    }

    /// The whole of `day`, structured as a journal entry.
    static func journalPlan(chunks: [ChunkRecord], day: String, model: String, maskNames: Bool = false, now: Date = Date()) -> TierTwoPlan {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty && $0.isOn(day) }.sorted { $0.wallStart < $1.wallStart }
        let question = "Write my private journal entry for today."
        let (sent, sentQuestion, masking) = masked(Array(stored.prefix(summaryCap)), query: question, day: stored, enabled: maskNames)
        let snippets = sent.map { Snippet(time: $0.stamp(now: now), text: $0.transcript ?? "", chunkID: $0.id) }
        let request = MuseRequest(model: model, developer: journalRules + maskingNote(masking),
                                  user: userMessage(query: sentQuestion, selected: sent, grouped: true, now: now),
                                  schemaName: EchoSchemas.journalName, schemaJSON: EchoSchemas.journal, maxCompletionTokens: 4000)
        return TierTwoPlan(intent: .summary, snippets: snippets, selectionReason: "the whole day, because a journal entry needs all of it",
                           request: request, masking: masking)
    }
}
