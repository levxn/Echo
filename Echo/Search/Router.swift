import Foundation

enum Tier: String {
    case local        // Tier 0: answered on this phone from retrieval alone
    case onDevice     // Tier 1: on-device Muse Glimmer (design only, never selected in this demo)
    case cloud        // Tier 2: Muse Spark through the Meta Model API
}

struct RouteDecision {
    let tier: Tier
    let reason: String
    let signals: [String]
}

/// Rules, not a model: decides where a question is answered.
enum Router {
    /// Words that signal the answer has to be assembled across the day rather than looked up.
    private static let synthesisMarkers: [(pattern: String, label: String)] = [
        (#"\bsummar(?:y|ize|ise)\b"#, "summarize"), (#"\brecap\b"#, "recap"), (#"\boverview\b"#, "overview"),
        (#"\beverything\b"#, "everything"), (#"\ball\b"#, "all"), (#"\bevery\b"#, "every"),
        (#"\bpromis(?:e|ed|es)\b"#, "promises"), (#"\bcommit(?:ment|ments|ted)?\b"#, "commitments"),
        (#"\baction items?\b"#, "action items"), (#"\bto-?dos?\b"#, "to-do"), (#"\btomorrow\b"#, "tomorrow"),
        (#"\bthis week\b"#, "this week"), (#"\boverall\b"#, "overall"), (#"\bwhat should i\b"#, "what should I"),
        (#"\bremind\b"#, "remind"), (#"\bhow many\b"#, "counting"),
    ]

    static let coverageThreshold = 0.66

    static func route(query: String, outcome: RetrievalOutcome) -> RouteDecision {
        let q = query.lowercased()
        let markers = synthesisMarkers.filter { q.range(of: $0.pattern, options: .regularExpression) != nil }.map(\.label)
        if !markers.isEmpty {
            return RouteDecision(tier: .cloud,
                                 reason: "This needs synthesis across your day (“\(markers[0])”), which is more than a lookup.",
                                 signals: markers)
        }
        if outcome.timeAnchored, outcome.knownTerms.isEmpty {
            return RouteDecision(tier: .local, reason: "Answered from what was captured \(outcome.timeWindow?.label ?? "then").",
                                 signals: ["time-anchored"])
        }
        let lexicalHit = outcome.hits.contains { !$0.matchedTerms.isEmpty }
        if lexicalHit, outcome.coverage >= coverageThreshold {
            var signals = ["coverage \(Int((outcome.coverage * 100).rounded()))%"]
            if outcome.timeAnchored { signals.append("time-anchored") }
            if !outcome.unknownTerms.isEmpty { signals.append("ignored: " + outcome.unknownTerms.joined(separator: ", ")) }
            return RouteDecision(tier: .local, reason: "Found a direct match in your transcripts, so nothing needs to leave this phone.",
                                 signals: signals)
        }
        return RouteDecision(tier: .cloud,
                             reason: outcome.hits.isEmpty ? "Nothing in today's transcripts matches closely enough."
                                                          : "Only a weak local match (\(Int((outcome.coverage * 100).rounded()))% of the key terms).",
                             signals: ["weak local match"])
    }
}
