import Foundation

/// A person named in the day's conversations, with the moments that name came up in.
struct Person: Identifiable, Equatable, Sendable {
    /// The name as it was first heard ("Priya Sharma"); the words are what is searched for in each moment.
    let name: String
    let words: [String]
    /// Moments that mention them, in time order.
    let momentIDs: [String]
    let firstLabel: String
    let lastLabel: String
    var id: String { words.joined(separator: " ").lowercased() }
    var count: Int { momentIDs.count }
}

/// Names the person has said are not people (a word the recognizer got wrong), kept on this phone until the day is forgotten.
nonisolated enum PeopleIgnore {
    static let key = "echo.peopleIgnored"

    static func ids(from raw: String) -> Set<String> { Set(raw.split(separator: "\n").map(String.init)) }
    static func raw(adding id: String, to raw: String) -> String { (ids(from: raw).union([id])).sorted().joined(separator: "\n") }
    static func visible(_ people: [Person], ignoring raw: String) -> [Person] {
        let hidden = ids(from: raw)
        return people.filter { !hidden.contains($0.id) }
    }
}

/// Who the day's conversations mention, found on the phone with the same name tagger masking uses. Echo doesn't tell
/// speakers apart, so this is the people spoken about or to, not a guest list, and a name the recognizer got wrong
/// is listed as it was heard.
nonisolated enum PeopleIndex {
    private static let titleWords: Set<String> = ["mr", "mister", "dr", "doctor", "mrs", "missus", "ms", "miss"]

    /// Lowercased words of a transcript with possessives and punctuation removed ("Priya's," becomes "priya").
    static func words(in text: String) -> Set<String> {
        var out: Set<String> = []
        for raw in text.split(whereSeparator: { !($0.isLetter || $0 == "'" || $0 == "’") }) {
            var w = raw.lowercased()
            for suffix in ["'s", "’s"] where w.hasSuffix(suffix) { w.removeLast(suffix.count) }
            w = w.trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
            if !w.isEmpty { out.insert(w) }
        }
        return out
    }

    /// `userName` is the profile name: the wearer isn't listed among the people they talked to.
    static func build(from chunks: [ChunkRecord], userName: String = "") -> [Person] {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }.sorted { ($0.dayId, $0.wallStart) < ($1.dayId, $1.wallStart) }
        guard !stored.isEmpty else { return [] }
        let texts = stored.map { $0.transcript ?? "" }

        // Which words are names: what masking would hide, so the two features never disagree.
        let spellings = Pseudonymizer.build(question: "", texts: texts).entries.map(\.original)
        guard !spellings.isEmpty else { return [] }
        let valid = Dictionary(spellings.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })

        // Words said together as one name ("Priya Sharma") belong to one person.
        var parent: [String: String] = Dictionary(uniqueKeysWithValues: valid.keys.map { ($0, $0) })
        func find(_ x: String) -> String { var r = x; while parent[r] != r, let p = parent[r] { r = p }; return r }
        for text in texts {
            for mention in TextNormalizer.personNames(in: text) {
                let ws = mention.name.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }).map { $0.lowercased() }
                    .filter { valid[$0] != nil && !titleWords.contains($0) }
                for w in ws.dropFirst() { parent[find(w)] = find(ws[0]) }
            }
        }

        var groups: [String: [String]] = [:]       // root -> words, first heard first
        for spelling in spellings { groups[find(spelling.lowercased()), default: []].append(spelling.lowercased()) }

        let tokens = stored.map { words(in: $0.transcript ?? "") }
        var people: [Person] = []
        for (_, ws) in groups {
            if ProfileLogic.isSamePerson(ws.joined(separator: " "), as: userName) { continue }
            let hits = stored.indices.filter { i in ws.contains { tokens[i].contains($0) } }
            guard let first = hits.first, let last = hits.last else { continue }
            people.append(Person(name: ws.compactMap { valid[$0] }.joined(separator: " "), words: ws, momentIDs: hits.map { stored[$0].id },
                                 firstLabel: stored[first].stamp(), lastLabel: stored[last].stamp()))
        }
        return people.sorted { $0.count != $1.count ? $0.count > $1.count : $0.firstLabel < $1.firstLabel }
    }

    /// The commitments that were said to this person or mention them.
    static func promises(for person: Person, in promises: [Promise]) -> [Promise] {
        promises.filter { p in
            let said = words(in: (p.toWhom ?? "") + " " + p.sentence)
            return person.words.contains { said.contains($0) }
        }
    }
}
