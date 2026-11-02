import Foundation

/// What to know before you see someone: when you last talked and about what, what you still owe them, and what comes up
/// between you. Worked out on the phone from what was heard, with plain rules (no model, nothing sent).
struct Briefing: Equatable {
    struct LastTime: Equatable {
        let dayId: String
        let when: String        // "A week ago", "Yesterday"
        let gist: String
    }

    let person: String
    let lastTime: LastTime?
    /// Things you said you would do that involve them and aren't ticked off.
    let youOwe: [String]
    /// Things they said they would do, when their voice is known by name.
    let theyOwe: [String]
    let topics: [String]
    let moments: Int

    var isEmpty: Bool { lastTime == nil && youOwe.isEmpty && theyOwe.isEmpty }

    /// For a notification or a one-line preview.
    var summary: String {
        var parts: [String] = []
        if let last = lastTime { parts.append("Last time (\(last.when.lowercased())): “\(last.gist)”") }
        if let first = youOwe.first { parts.append("You owe them: \(first)" + (youOwe.count > 1 ? " (+\(youOwe.count - 1) more)" : "")) }
        if let first = theyOwe.first { parts.append("They owe you: \(first)") }
        return parts.joined(separator: " ")
    }
}

nonisolated enum BriefingBuilder {
    /// `done` are the promises already ticked off. `myVoice` is the person's own voice id, once known, so "you owe" means what
    /// *they* said; `voices` lets a voice named after the person stand for them, so "they owe you" can be told.
    @MainActor
    static func make(for person: Person, chunks: [ChunkRecord], promises: [Promise], done: Set<String> = [], myVoice: String? = nil,
                     voiceNamed: (String) -> String? = { _ in nil }, now: Date = Date()) -> Briefing {
        let words = Set(person.words)
        let said = chunks.filter { person.momentIDs.contains($0.id) && $0.status == .stored }
        let today = DayID.today(now: now)
        // The most recent day other than today they came up; today's own talk only if there is nothing earlier.
        let days = Set(said.map(\.dayId)).sorted()
        let pick = days.last { $0 != today && !$0.isEmpty } ?? days.last
        var last: Briefing.LastTime?
        if let pick {
            let thatDay = said.filter { $0.dayId == pick }
            if let best = EpisodeBuilder.build(from: thatDay).max(by: { $0.chunks.count < $1.chunks.count }) {
                last = Briefing.LastTime(dayId: pick, when: DayID.longLabel(pick, now: now), gist: best.gist)
            }
        }

        func involves(_ p: Promise) -> Bool {
            let tokens = PeopleIndex.words(in: (p.toWhom ?? "") + " " + p.sentence)
            return !words.isDisjoint(with: tokens)
        }
        let open = promises.filter { $0.kind == .commitment && !done.contains($0.id) && involves($0) }
        let theirVoice = voiceNamed(person.name)
        let mine = open.filter { myVoice == nil ? $0.speakerId != theirVoice : $0.speakerId == myVoice }
        let theirs = theirVoice.map { id in open.filter { $0.speakerId == id } } ?? []

        var topics: [String] = []
        for episode in EpisodeBuilder.build(from: said) {
            for k in episode.keywords where !words.contains(k.lowercased()) && !topics.contains(k) { topics.append(k) }
        }
        return Briefing(person: person.name, lastTime: last, youOwe: mine.map(\.sentence), theyOwe: theirs.map(\.sentence),
                        topics: Array(topics.prefix(3)), moments: said.count)
    }
}
