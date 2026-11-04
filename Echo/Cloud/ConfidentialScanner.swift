import Foundation

/// The kinds of confidential detail Echo keeps on the phone. Each one is replaced by a placeholder before any text goes to Muse
/// and is put back only inside a draft the person is looking at, on this phone.
nonisolated enum ConfidentialKind: String, CaseIterable, Codable, Sendable {
    case password, pin, code, card, account, id, key, email, phone

    /// The word in the placeholder: `[PASSWORD_1]`.
    var token: String {
        switch self {
        case .password: "PASSWORD"
        case .pin: "PIN"
        case .code: "CODE"
        case .card: "CARD"
        case .account: "ACCOUNT"
        case .id: "ID"
        case .key: "KEY"
        case .email: "EMAIL"
        case .phone: "PHONE"
        }
    }

    /// For the review sheet and the ledger: "a password", "2 phone numbers".
    func noun(_ count: Int) -> String {
        let (one, many): (String, String) = switch self {
        case .password: ("password", "passwords")
        case .pin: ("PIN", "PINs")
        case .code: ("one-time code", "one-time codes")
        case .card: ("card number", "card numbers")
        case .account: ("bank detail", "bank details")
        case .id: ("ID number", "ID numbers")
        case .key: ("secret key", "secret keys")
        case .email: ("email address", "email addresses")
        case .phone: ("phone number", "phone numbers")
        }
        return count == 1 ? one : many
    }
}

extension ConfidentialKind {
    /// "a password and a card number" / "2 phone numbers", from how many of each were held back (counts only).
    static func summary(_ counts: [ConfidentialKind: Int]) -> String {
        let parts = allCases.compactMap { kind -> String? in
            guard let n = counts[kind], n > 0 else { return nil }
            return n == 1 ? "a \(kind.noun(1))" : "\(n) \(kind.noun(n))"
        }
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        default: return parts.dropLast().joined(separator: ", ") + " and " + parts[parts.count - 1]
        }
    }

    /// The same, from what the ledger stores (kind name to count).
    static func summary(stored: [String: Int]) -> String {
        summary(Dictionary(stored.compactMap { key, n in ConfidentialKind(rawValue: key).map { ($0, n) } }, uniquingKeysWith: +))
    }
}

/// One confidential piece of a piece of text.
nonisolated struct ConfidentialSpan: Equatable, Sendable {
    let range: NSRange
    let kind: ConfidentialKind
    let text: String
    /// Found because a cue word introduced it ("my password is …"), which is stronger evidence than a bare pattern.
    var cued = false
}

/// The confidential details found in a request, with their placeholders. Lives in memory for that one request and is never stored.
nonisolated struct SecretMask: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        let original: String
        let token: String
        let kind: ConfidentialKind
    }

    var entries: [Entry] = []
    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// How many of each kind were held back (counts only: this is what the review sheet and the ledger show).
    var heldBack: [ConfidentialKind: Int] {
        Dictionary(entries.map { ($0.kind, 1) }, uniquingKeysWith: +)
    }

    /// "a password and a card number" / "2 phone numbers".
    var summary: String { ConfidentialKind.summary(heldBack) }

    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"\[\s*(PASSWORD|PIN|CODE|CARD|ACCOUNT|ID|KEY|EMAIL|PHONE)[_ ]?(\d+)\s*\]|\b(PASSWORD|PIN|CODE|CARD|ACCOUNT|KEY|EMAIL|PHONE)_(\d+)\b"#,
        options: .caseInsensitive)

    /// Puts the real values back. Tolerates the model changing case or dropping the brackets; a placeholder this request never used is
    /// left as written. Call this only for a draft on this phone.
    func restore(_ text: String) -> String {
        guard !entries.isEmpty else { return text }
        var out = text
        for match in Self.tokenPattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let g = match.range(at: 1).location != NSNotFound ? 1 : 3
            guard let whole = Range(match.range, in: out), let name = Range(match.range(at: g), in: out),
                  let number = Range(match.range(at: g + 1), in: out), let n = Int(out[number]),
                  let entry = entries.first(where: { $0.token == "[\(out[name].uppercased())_\(n)]" }) else { continue }
            out.replaceSubrange(whole, with: entry.original)
        }
        return out
    }
}

/// Finds the confidential part of a string with plain rules (no model), fast enough to run on every request.
///
/// It errs toward redacting: a wrongly hidden word costs a slightly vaguer draft, a leaked password costs far more. It is best effort,
/// and the review sheet always shows exactly what would be sent.
nonisolated enum ConfidentialScanner {
    private static let digitWords = "zero|oh|one|two|three|four|five|six|seven|eight|nine"
    private static let connector = #"(?:\s*(?:is|was|will be|would be|=|:)\s*[:\-]?\s*)"#
    /// Digits, or spoken digits ("four eight two one"), at least three of them.
    private static let digitRun = #"((?:\d[\s\-]?){2,12}\d|(?:(?:\#(digitWords))\b[\s,\-]*){3,12})"#
    /// "is", "was", "=", ":" or simply a space, between a cue word and its value.
    private static let optionalConnector = #"(?:\s*(?:is|was|=|:)\s*|\s+)"#
    /// Words that end a spoken password ("my password is hunter2 and I'll send it").
    private static let stopWords: Set<String> = ["and", "but", "so", "then", "because", "which", "that", "to", "for", "or", "also", "if", "when", "while", "since", "i", "i'll", "we"]

    private static func rx(_ pattern: String, _ options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: options)
    }

    /// Cue words followed by the secret itself (capture group 1).
    private static let cued: [(ConfidentialKind, NSRegularExpression)] = [
        (.password, rx(#"\b(?:pass(?:word|phrase|code)|passwd|pwd)\b(?:\s+(?:for|to|on|of)\s+(?:[\w'’\-]+\s+){1,3}?)?"# + connector + #"([^\s.,;!?]+(?:\s+[^\s.,;!?]+){0,4})"#)),
        (.password, rx(#"\b(?:pass(?:word|phrase|code)|passwd|pwd)\s+(\S*\d\S*)"#)),
        (.pin, rx(#"\bpin(?:\s+(?:code|number))?\b"# + optionalConnector + digitRun)),
        (.code, rx(#"\b(?:otp|one[- ]time (?:code|password|passcode|pin)|(?:verification|security|authentication|auth|confirmation|login|sms|reset|activation|access|2fa) code|cvv2?|cvc|(?:the|my|your) code)\b"# + optionalConnector + digitRun)),
        (.account, rx(#"\b(?:account|acct|routing|sort code|swift|iban|ifsc|bic)(?: number| no\.?| code)?\b"# + connector + #"([A-Z0-9][A-Z0-9 \-]{4,32}[A-Z0-9])"#)),
        (.id, rx(#"\b(?:ssn|social security(?: number)?|aadhaar|aadhar|pan|passport|national id|driver'?s? licen[cs]e|tax id|tin)(?: number| no\.?| card)?\b"# + connector + #"([A-Z0-9][A-Z0-9 \-]{3,20}[A-Z0-9])"#)),
        (.key, rx(#"\b(?:api[ \-]?key|access[ \-]?(?:key|token)|secret(?: key)?|(?:auth|bearer|refresh|private)(?: token| key)|token|client secret)\b"# + connector + #"(\S{8,})"#)),
        (.key, rx(#"\bbearer\s+([A-Za-z0-9._\-]{16,})"#)),
    ]

    private static let email = rx(#"[A-Z0-9._%+\-]+@[A-Z0-9\-]+(?:\.[A-Z0-9\-]+)*\.[A-Z]{2,}"#)
    private static let spokenEmail = rx(#"\b[A-Z0-9._\-]+ at [A-Z0-9\-]+(?: dot [A-Z0-9\-]+)* dot (?:com|org|net|edu|gov|io|in|co|uk|de|us)\b"#)
    private static let iban = rx(#"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#, [])
    private static let ssn = rx(#"\b\d{3}-\d{2}-\d{4}\b"#)
    private static let aadhaar = rx(#"(?<![\d\-])(?<!\d\s)\d{4}\s\d{4}\s\d{4}(?![\s\-]?\d)"#)
    private static let pan = rx(#"\b[A-Z]{5}\d{4}[A-Z]\b"#, [])
    private static let longToken = rx(#"\b(?=[A-Za-z0-9_\-]*\d)(?=[A-Za-z0-9_\-]*[A-Za-z])[A-Za-z0-9_\-]{24,}\b"#, [])
    private static let digitCandidate = rx(#"(?<![\d\-])\+?(?:\(?\d[\d\s().\-]{6,}\d)(?![\d\-])"#)
    private static let spokenDigits = rx(#"\b(?:(?:\#(digitWords))\b[\s,\-]*){7,20}"#)

    private static func luhn(_ digits: String) -> Bool {
        var sum = 0
        for (i, ch) in digits.reversed().enumerated() {
            guard var d = ch.wholeNumberValue else { return false }
            if i % 2 == 1 { d *= 2; if d > 9 { d -= 9 } }
            sum += d
        }
        return sum % 10 == 0
    }

    private static let wordValue: [String: String] = ["zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4",
                                                      "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]

    private static func digits(in s: String) -> String {
        var out = ""
        for token in s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            if let v = wordValue[String(token)] { out += v } else { out += token.filter(\.isNumber) }
        }
        return out
    }

    private static let cueWords = ["pass", "pwd", "pin", "otp", "code", "cvv", "cvc", "account", "acct", "routing", "sort", "swift", "iban", "ifsc",
                                   "bic", "ssn", "social", "aadhaar", "aadhar", "passport", "licen", "national id", "tax id", "tin", "token", "secret",
                                   "api", "bearer", "@", " at ", "key"]

    /// A quick look that lets an ordinary sentence skip every pattern: it has no digit, none of the cue words, and no run of spoken digits.
    private static func mightContainSecret(_ text: String) -> Bool {
        if text.contains(where: \.isNumber) { return true }
        let lower = text.lowercased()
        if cueWords.contains(where: { lower.contains($0) }) { return true }
        var run = 0
        for token in lower.split(whereSeparator: { !$0.isLetter }) {
            if wordValue[String(token)] != nil { run += 1; if run >= 3 { return true } } else { run = 0 }
        }
        return false
    }

    /// Every confidential span in `text`, in order, not overlapping.
    static func scan(_ text: String) -> [ConfidentialSpan] {
        guard text.count >= 4, mightContainSecret(text) else { return [] }
        let full = NSRange(text.startIndex..., in: text)
        let ns = text as NSString
        var spans: [ConfidentialSpan] = []
        func add(_ kind: ConfidentialKind, _ range: NSRange, cued: Bool = false) {
            guard range.location != NSNotFound, range.length > 0 else { return }
            spans.append(ConfidentialSpan(range: range, kind: kind, text: ns.substring(with: range), cued: cued))
        }

        for (kind, regex) in cued {
            for m in regex.matches(in: text, range: full) where m.numberOfRanges > 1 {
                var range = m.range(at: 1)
                var value = ns.substring(with: range)
                if kind == .password {
                    // a spoken password is a few words, but it stops where the sentence goes on ("… hunter2 and I will send it")
                    let words = value.split(separator: " ", omittingEmptySubsequences: true)
                    if let cut = words.enumerated().first(where: { $0.offset > 0 && stopWords.contains($0.element.lowercased()) })?.offset {
                        value = words[..<cut].joined(separator: " ")
                        range = NSRange(location: range.location, length: (value as NSString).length)
                    }
                }
                switch kind {
                case .account, .id: if digits(in: value).count < (kind == .id ? 4 : 6) { continue }
                case .pin, .code: if digits(in: value).count < 3 { continue }
                default: break
                }
                add(kind, range, cued: true)
            }
        }
        for m in email.matches(in: text, range: full) { add(.email, m.range) }
        for m in spokenEmail.matches(in: text, range: full) { add(.email, m.range) }
        for m in iban.matches(in: text, range: full) { add(.account, m.range) }
        for m in ssn.matches(in: text, range: full) { add(.id, m.range) }
        for m in aadhaar.matches(in: text, range: full) { add(.id, m.range) }
        for m in pan.matches(in: text, range: full) { add(.id, m.range) }
        for m in longToken.matches(in: text, range: full) { add(.key, m.range) }

        for m in digitCandidate.matches(in: text, range: full) {
            let raw = ns.substring(with: m.range)
            let d = raw.filter(\.isNumber)
            if raw.range(of: #"^\d{4}-\d{1,2}-\d{1,2}$"#, options: .regularExpression) != nil { continue }   // a date
            if (13...19).contains(d.count), luhn(d) { add(.card, m.range); continue }
            let grouped = raw.contains("+") || raw.contains("(") || raw.filter({ " .-".contains($0) }).count >= 2
            if (10...15).contains(d.count) || (grouped && (8...15).contains(d.count)) { add(.phone, m.range) }
        }
        for m in spokenDigits.matches(in: text, range: full) {
            let d = digits(in: ns.substring(with: m.range))
            if (13...19).contains(d.count), luhn(d) { add(.card, m.range) } else if (7...15).contains(d.count) { add(.phone, m.range) }
        }

        // Where two overlap, a cued match beats a bare pattern, and otherwise the longer one wins.
        let ordered = spans.sorted { a, b in a.range.location != b.range.location ? a.range.location < b.range.location : a.range.length > b.range.length }
        var kept: [ConfidentialSpan] = []
        for span in ordered {
            if let last = kept.last, NSIntersectionRange(last.range, span.range).length > 0 {
                if (span.cued && !last.cued) || (span.cued == last.cued && span.range.length > last.range.length) { kept[kept.count - 1] = span }
                continue
            }
            kept.append(span)
        }
        return kept
    }

    /// The same texts with every confidential part replaced by a placeholder, and the mask that can put them back. The texts share one
    /// numbering, in reading order, so the same value gets the same placeholder everywhere in a request.
    static func redact(_ texts: [String]) -> (texts: [String], mask: SecretMask) {
        var entries: [SecretMask.Entry] = []
        var counters: [ConfidentialKind: Int] = [:]
        var assigned: [String: String] = [:]
        let redacted = texts.map { text -> String in
            let spans = scan(text)
            guard !spans.isEmpty else { return text }
            let ns = text as NSString
            var result = ""
            var cursor = 0
            for span in spans {
                result += ns.substring(with: NSRange(location: cursor, length: span.range.location - cursor))
                let key = "\(span.kind.rawValue)|\(span.text.lowercased())"
                let token: String
                if let existing = assigned[key] { token = existing } else {
                    counters[span.kind, default: 0] += 1
                    token = "[\(span.kind.token)_\(counters[span.kind]!)]"
                    assigned[key] = token
                    entries.append(SecretMask.Entry(original: span.text, token: token, kind: span.kind))
                }
                result += token
                cursor = span.range.location + span.range.length
            }
            return result + ns.substring(from: cursor)
        }
        return (redacted, SecretMask(entries: entries))
    }
}
