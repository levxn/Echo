import Foundation

enum Tier: String {
    case local        // Tier 0: answered on this phone from retrieval alone
    case onDevice     // Tier 1: on-device Muse Glimmer (design only, never selected in this demo)
    case cloud        // Tier 2: Muse Spark through the Meta Model API
}

/// Why a question was routed the way it was; the cloud planner picks snippets by intent.
enum Intent: String {
    case lookup        // answered locally
    case commitments   // promises, to-dos, "what should I do"
    case summary       // recap or overview of the day
    case general       // weak local match
}

struct RouteDecision {
    let tier: Tier
    let reason: String
    let signals: [String]
    var intent: Intent = .lookup
}

/// Rules, not a model: decides where a question is answered.
enum Router {
    /// Words that signal the answer has to be assembled across the day rather than looked up.
    private static let synthesisMarkers: [(pattern: String, label: String, intent: Intent)] = [
        (#"\bsummar(?:y|ize|ise)\b"#, "summarize", .summary), (#"\brecap\b"#, "recap", .summary),
        (#"\boverview\b"#, "overview", .summary), (#"\beverything\b"#, "everything", .summary),
        (#"\ball\b"#, "all", .summary), (#"\bevery\b"#, "every", .summary), (#"\boverall\b"#, "overall", .summary),
        (#"\bthis week\b"#, "this week", .summary), (#"\bhow many\b"#, "counting", .summary),
        (#"\bpromis(?:e|ed|es)\b"#, "promises", .commitments), (#"\bcommit(?:ment|ments|ted)?\b"#, "commitments", .commitments),
        (#"\baction items?\b"#, "action items", .commitments), (#"\bto-?dos?\b"#, "to-do", .commitments),
        (#"\btomorrow\b"#, "tomorrow", .commitments), (#"\bwhat should i\b"#, "what should I", .commitments),
        (#"\bremind\b"#, "remind", .commitments),
        (#"\bwhy did (?:we|i) (?:decide|choose|pick|go|agree)\b"#, "why we decided", .general),
    ]

    static let coverageThreshold = 0.66

    static func route(query: String, outcome: RetrievalOutcome) -> RouteDecision {
        let q = query.lowercased()
        let matched = synthesisMarkers.filter { q.range(of: $0.pattern, options: .regularExpression) != nil }
        let markers = matched.map(\.label)
        if !markers.isEmpty {
            // Commitments is the more specific intent, so it wins when both kinds of marker appear.
            let intent: Intent = matched.contains { $0.intent == .commitments } ? .commitments : (matched.allSatisfy { $0.intent == .general } ? .general : .summary)
            return RouteDecision(tier: .cloud,
                                 reason: "This needs synthesis across your day (“\(markers[0])”), which is more than a lookup.",
                                 signals: markers, intent: intent)
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
                             signals: ["weak local match"], intent: .general)
    }
}
