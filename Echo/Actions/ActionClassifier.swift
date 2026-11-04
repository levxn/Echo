import Foundation

/// The words that decide what kind of action a sentence is, and how to title it. Plain rules, no model.
nonisolated enum ActionClassifier {
    private static func rx(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern, options: .caseInsensitive) }
    private static func has(_ regex: NSRegularExpression, _ text: String) -> Bool { regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil }
    private static func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    // MARK: Commitments ("I will …")

    private static let cuePrefix = rx(#"^(?:(?:and|also|so|then|but|well|okay|right|great|thanks|sure|yes|yeah)[\s,]+)*(?:i(?:['’]ll| will| am going to|['’]m going to| promise to| promise)\s+(?:(?:also|definitely|just|really|still|first)\s+)*|remember to\s+|don['’]?t forget to\s+|please remember to\s+)"#)
    private static let promiseTail = rx(#"[\s,.]*(?:that['’]?s a promise|i promise|promise)[.!]*$"#)
    private static let objectPronoun = rx(#"^(send|text|give|bring|show|tell|email|message|forward|get|buy)\s+(?:you|him|her|them)\s+"#)

    private static let call = rx(#"\bcall(?:ing)?\b|\bphone\b|\bring\b"#)
    private static let email = rx(#"\be-?mail\b"#)
    private static let documentNoun = rx(#"\b(?:specification|spec|document|contract|invoice|report|proposal|slides|deck|presentation|file|files|pdf|attachment|agreement|quote|estimate|budget|resume|notes|minutes|draft)\b"#)
    private static let sendDocument = rx(#"\bsend\b.{0,40}\b(?:specification|spec|document|contract|invoice|report|proposal|slides|deck|presentation|file|files|pdf|attachment|agreement|quote|estimate|budget|resume|notes|minutes|draft)\b"#)
    private static let messageVerb = rx(#"\b(?:text|message|whatsapp|ping|dm|reply|respond|let (?:you|him|her|them) know|tell (?:you|him|her|them)|get back to you|(?:give|send) you (?:a |an |my |the )?(?:final )?(?:answer|reply|response))\b"#)
    private static let sendThing = rx(#"\bsend\b.{0,30}\b(?:link|recipe|photos?|pictures?|address|location|number|details|update|invite|video|voucher|it)\b"#)
    private static let meetVerb = rx(#"\b(?:meet|visit|attend|join|see|catch up with)\b"#)

    /// What kind of thing a commitment is. `when` is the time said in the sentence, if any.
    static func kind(ofCommitment clause: String, when: EventWhen?) -> ActionKind {
        if has(call, clause) { return .call }
        if has(email, clause) || has(sendDocument, clause) { return .email }
        if has(messageVerb, clause) || has(sendThing, clause) { return .message }
        if has(meetVerb, clause), when?.hasClock == true { return .calendar }
        return .todo
    }

    /// "Send the API specification", from "Right I will send you the API specification by Wednesday noon, that's a promise."
    static func title(ofClause sentence: String, kind: ActionKind, person: String?, when: EventWhen?) -> String {
        var t = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        t = replacing(cuePrefix, in: t, with: "")
        t = replacing(promiseTail, in: t, with: "")
        if let phrase = when?.phrase, !phrase.isEmpty,
           let regex = try? NSRegularExpression(pattern: #"\s*(?:\b(?:on|by|before|at|this|next|until)\s+)?"# + NSRegularExpression.escapedPattern(for: phrase), options: .caseInsensitive) {
            t = replacing(regex, in: t, with: "")
        }
        t = replacing(objectPronoun, in: t, with: "$1 ")
        t = replacing(rx(#"\s+if\s+.*$"#), in: t, with: "")   // "text you the link if you want to join" → "text the link"
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;!?"))
        if t.count > 54, let cut = t.range(of: #"\s(?:so|because|which|that|while|and|but|if)\s"#, options: .regularExpression), t.distance(from: t.startIndex, to: cut.lowerBound) > 12 {
            t = String(t[..<cut.lowerBound])
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;!?"))
        guard let first = t.first else { return "" }
        t = first.uppercased() + t.dropFirst()
        if let person, [.email, .message].contains(kind), !t.localizedCaseInsensitiveContains(person) { t += " to \(person)" }
        return t
    }

    // MARK: Calls

    private static let kin = ["grandma", "grandmother", "grandpa", "grandfather", "mom", "mum", "mother", "dad", "father", "sister", "brother", "aunt", "uncle", "wife", "husband"]
    private static let callTarget = rx(#"\bcall(?:ing)?\s+(?:up\s+)?(.+?)(?:\s+(?:tomorrow|today|tonight|this|next|on|at|and|in|before|after|when|first|later|about|to)\b|[,.;]|$)"#)

    /// Who is being called: "Grandma", "her office" (→ the name just mentioned, "Doctor Patel's office"), "the plumber".
    static func callTargetName(in sentence: String, contextName: String?) -> String? {
        guard let m = callTarget.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)), let r = Range(m.range(at: 1), in: sentence) else { return contextName }
        var target = String(sentence[r]).trimmingCharacters(in: .whitespaces)
        let lower = target.lowercased()
        if ["her", "him", "them", "they", "it"].contains(lower) { return contextName }
        if lower.hasPrefix("her ") || lower.hasPrefix("his ") || lower.hasPrefix("their ") {
            let rest = target.split(separator: " ", maxSplits: 1).last.map(String.init) ?? ""
            return contextName.map { "\($0)’s \(rest)" } ?? rest.capitalized
        }
        if let k = kin.first(where: { lower == $0 }) { target = k == "grandmother" ? "Grandma" : k.capitalized }
        else { target = target.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ") }
        return target.isEmpty ? contextName : target
    }

    // MARK: Requests ("Can you bring the salad?")

    private static let requestVerbs = "send|bring|call|check|review|share|forward|email|text|book|pay|pick|get|buy|order|give|make|take|help|remind|look|find|tell|ask|drive|fix|set|update|submit|finish|join|meet|reply|confirm|cancel|move|add|write|prepare|print|sign"
    private static let requestPattern = rx(#"(?:\b(?:can|could|would|will) you(?: please)?|\bplease)\s+((?:\#(requestVerbs))\b.+?)\s*[?.!]*$"#)

    /// What was asked of the listener, without the vocative ("bring the salad, sweetheart" → "Bring the salad").
    static func request(in sentence: String) -> String? {
        guard let m = requestPattern.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)), let r = Range(m.range(at: 1), in: sentence) else { return nil }
        var t = String(sentence[r])
        if let cut = t.range(of: #"\s*,\s*(?:sweetheart|honey|dear|darling|buddy|mate|man|guys?|everyone)\b.*$"#, options: [.regularExpression, .caseInsensitive]) { t.removeSubrange(cut) }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;!?"))
        guard let first = t.first, t.split(separator: " ").count >= 3 else { return nil }   // "send it" says nothing on its own
        return first.uppercased() + t.dropFirst()
    }

    // MARK: Shopping lists

    private static let shoppingCue = rx(#"\b(?:groceries|grocery|shopping|supplies|(?:we|you|i)(?: also)? (?:need|needed|run out of|ran out of|are out of|have to (?:buy|get)|should (?:buy|get)|must (?:buy|get))|pick up|buy|get)\b[\s:]*(?:some |more )?(?:groceries |supplies |stuff |things )?(.+)$"#)

    /// The items of a list said in a sentence ("We also need groceries eggs, olive oil, and oranges for the juice" → three items).
    static func shoppingItems(in sentence: String) -> [String] {
        guard let m = shoppingCue.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)), let r = Range(m.range(at: 1), in: sentence) else { return [] }
        let stop: Set<String> = ["to", "talk", "think", "decide", "do", "go", "be", "see", "make", "discuss", "meet"]
        let parts = String(sentence[r]).replacingOccurrences(of: ".", with: " ")
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .flatMap { $0.components(separatedBy: " and ") }
        var items: [String] = []
        for part in parts {
            var item = part.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["some ", "a ", "an ", "the ", "more ", "also "] where item.lowercased().hasPrefix(prefix) { item = String(item.dropFirst(prefix.count)) }
            if let cut = item.range(of: #"\s(?:for|from|at|in|on|with|so|because|when|before|after)\s.*$"#, options: [.regularExpression, .caseInsensitive]) { item.removeSubrange(cut) }
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;!?"))
            if item.isEmpty { continue }   // "olive oil, and oranges" splits into an empty piece
            let words = item.split(separator: " ")
            guard words.count <= 3, !stop.contains(words[0].lowercased()) else { return [] }
            items.append(item.prefix(1).uppercased() + item.dropFirst())
        }
        return items.count >= 2 ? items : []
    }

    // MARK: Events

    private static let eventNoun = rx(#"\b(meeting|stand-?up|appointment|plumber|electrician|doctor|dentist|dinner|lunch|breakfast|party|birthday|anniversary|flight|train|interview|demo|kick-?off|presentation|wedding|concert|trip|delivery|pickup|deploy(?:ment)?|launch|release|check-?up|surgery|class|workshop|webinar|session|exam)\b"#)
    private static let possessiveBirthday = rx(#"([A-Za-z]+)['’]s\s+(birthday|anniversary)\b"#)

    struct EventDescription: Equatable, Sendable {
        let title: String
        let allDay: Bool
        let repeatsYearly: Bool
        let minutes: Int
    }

    /// The event a sentence describes ("a plumber to come on Friday", "your mother's birthday is on November 14"), if it names one.
    private static let offeredSlot = rx(#"\b(?:i can do it|we can do it|i can see you|i can fit you in|see you)\b"#)
    private static let dayWords = rx(#"monday|tuesday|wednesday|thursday|friday|saturday|sunday|tomorrow|today|tonight|january|february|march|april|may|june|july|august|september|october|november|december|\d{1,2}(?:st|nd|rd|th)"#)

    static func event(in sentence: String, when: EventWhen?) -> EventDescription? {
        guard let when else { return nil }
        // "I can do it next Tuesday at three": a slot offered for something already being arranged, with a day and a clock time
        if when.hasClock, has(offeredSlot, sentence), has(dayWords, when.phrase), !has(eventNoun, sentence) {
            return EventDescription(title: "Appointment", allDay: false, repeatsYearly: false, minutes: 45)
        }
        guard let m = eventNoun.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)), let r = Range(m.range(at: 1), in: sentence) else { return nil }
        let noun = String(sentence[r]).lowercased().replacingOccurrences(of: "-", with: "")
        let longTrip = ["trip", "birthday", "anniversary", "wedding"].contains(noun)
        // an event needs a clock time or a part of the day; a deployment or a launch needs only the day
        let partOfDay = when.phrase.range(of: #"morning|afternoon|evening|noon|night|first thing"#, options: [.regularExpression, .caseInsensitive]) != nil
        let dayIsEnough = ["deploy", "deployment", "launch", "release", "delivery"].contains(noun)
        guard when.hasClock || longTrip || partOfDay || dayIsEnough else { return nil }
        switch noun {
        case "birthday", "anniversary":
            let owner = possessiveBirthday.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)).flatMap { Range($0.range(at: 1), in: sentence) }.map { String(sentence[$0]) }
            let who = owner.map { ["your", "my", "his", "her"].contains($0.lowercased()) ? "" : $0.prefix(1).uppercased() + $0.dropFirst() + "’s " } ?? ""
            return EventDescription(title: who.isEmpty ? noun.capitalized : who + noun, allDay: true, repeatsYearly: true, minutes: 0)
        case "plumber", "electrician": return EventDescription(title: noun.capitalized + " visit", allDay: false, repeatsYearly: false, minutes: 60)
        case "doctor", "dentist": return EventDescription(title: noun.capitalized + " appointment", allDay: false, repeatsYearly: false, minutes: 45)
        case "trip", "wedding": return EventDescription(title: noun.capitalized, allDay: true, repeatsYearly: false, minutes: 0)
        case "deploy", "deployment", "launch", "release":
            return EventDescription(title: deployTitle(sentence, noun: noun, when: when), allDay: false, repeatsYearly: false, minutes: 60)
        default:
            let withWho = try? NSRegularExpression(pattern: #"\b(?:with|for)\s+([A-Z][a-z]+(?:\s[A-Z][a-z]+)?)"#)
            var title = noun.prefix(1).uppercased() + noun.dropFirst()
            if let w = withWho?.firstMatch(in: sentence, range: NSRange(sentence.startIndex..., in: sentence)), let wr = Range(w.range(at: 1), in: sentence) { title += " with \(sentence[wr])" }
            return EventDescription(title: title, allDay: false, repeatsYearly: false, minutes: noun == "dinner" ? 90 : 60)
        }
    }

    private static func deployTitle(_ sentence: String, noun: String, when: EventWhen) -> String {
        guard let r = sentence.range(of: noun, options: .caseInsensitive) else { return noun.capitalized }
        var rest = String(sentence[r.lowerBound...])
        if let cut = rest.range(of: #"\s+(?:on|at|this|next|tomorrow|by|before)\b"#, options: [.regularExpression, .caseInsensitive]) { rest = String(rest[..<cut.lowerBound]) }
        rest = rest.replacingOccurrences(of: "deploy a production", with: "Deploy to production", options: .caseInsensitive)
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }
}
