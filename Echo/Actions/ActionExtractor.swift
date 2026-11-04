import Foundation

/// Finds the things people said that someone could act on, with plain rules and no model: promises become to-dos, messages, emails and
/// calls; times and events become calendar entries; requests become to-dos; lists become shopping lists; other people's promises become
/// "waiting on". Everything is worked out on the phone from the transcripts.
nonisolated enum ActionExtractor {
    /// `myVoice` is the voice the person marked as theirs (nil until they have): without it, every promise is treated as theirs.
    /// `voiceName` gives the name the person has given to a voice, if any.
    static func extract(from chunks: [ChunkRecord], userName: String = "", myVoice: String? = nil, voiceName: (String) -> String? = { _ in nil },
                        now: Date = Date(), calendar: Calendar = .current) -> [ActionItem] {
        let stored = chunks.filter { $0.status == .stored && !($0.transcript ?? "").isEmpty }
            .sorted { ($0.dayId, $0.wallStart) < ($1.dayId, $1.wallStart) }
        let promises = Dictionary(PromiseExtractor.extract(from: chunks, userName: userName).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out: [ActionItem] = []

        for (i, chunk) in stored.enumerated() {
            let previous = i > 0 && stored[i - 1].dayId == chunk.dayId && chunk.wallStart - stored[i - 1].wallStart <= 60 ? stored[i - 1] : nil
            let reference = referenceDate(for: chunk, now: now, calendar: calendar)
            let isMine = myVoice == nil || chunk.speakerId.isEmpty || chunk.speakerId == myVoice
            let speaker = chunk.speakerId.isEmpty ? nil : voiceName(chunk.speakerId)
            let replyingTo = previous.flatMap { $0.speakerId != chunk.speakerId && !$0.speakerId.isEmpty ? $0 : nil }
            let addressee = promisesAddressee(before: i, in: stored, myVoice: myVoice, userName: userName)
            let aboutName = recentOtherName(before: i, in: stored, excluding: addressee, userName: userName)

            for (n, raw) in AnswerExtractor.split(chunk.transcript ?? "").enumerated() {
                let sentence = polish(raw)
                let when = EventTime.find(in: sentence, reference: reference, calendar: calendar)

                func item(_ kind: ActionKind, _ title: String, suffix: String = "") -> ActionItem {
                    ActionItem(id: "\(chunk.id)#a\(n)\(suffix)", kind: kind, title: title, quote: sentence, chunkID: chunk.id, dayId: chunk.dayId,
                               wallStart: chunk.wallStart, timeLabel: chunk.stamp(now: now), speakerId: chunk.speakerId)
                }
                func timed(_ a: ActionItem, _ w: EventWhen?) -> ActionItem {
                    var a = a
                    a.due = w?.date; a.dueText = w?.phrase.isEmpty == false ? w?.phrase : nil; a.hasClock = w?.hasClock ?? false
                    return a
                }

                if let promise = promises["\(chunk.id)#\(n)"] {
                    // Someone else's "I will" is a promise to wait on; their "remember to" or "don't forget to" is a reminder to the listener.
                    let waitingOn = !isMine && promise.kind == .commitment
                    let remindedBy = !isMine && promise.kind == .reminder
                    for (k, part) in compound(promise.sentence, reference: reference, calendar: calendar).enumerated() {
                        let partWhen = k == 0 && part.when == nil ? when : part.when
                        var kind = waitingOn ? .waiting : ActionClassifier.kind(ofCommitment: part.text, when: partWhen)
                        let addresseeName = promise.toWhom ?? replyingTo.flatMap { voiceName($0.speakerId) } ?? addressee
                        var title: String
                        var person: String? = nil
                        switch kind {
                        case .call:
                            person = ActionClassifier.callTargetName(in: part.text, contextName: aboutName)
                            title = person.map { "Call \($0)" } ?? "Make a call"
                        case .email, .message:
                            person = addresseeName
                            title = ActionClassifier.title(ofClause: part.text, kind: kind, person: person, when: partWhen)
                        default:
                            title = ActionClassifier.title(ofClause: part.text, kind: kind, person: nil, when: partWhen)
                        }
                        guard !title.isEmpty else { continue }
                        var allDay = false, yearly = false, minutes = 30
                        if isMine, kind == .todo, let ev = ActionClassifier.event(in: part.text, when: partWhen) {
                            kind = .calendar; title = ev.title; allDay = ev.allDay; yearly = ev.repeatsYearly; minutes = ev.minutes
                        }
                        if remindedBy, let speaker { title = replacingMe(in: title, with: speaker) }
                        var a = timed(item(kind, title, suffix: k == 0 ? "" : "b"), partWhen)
                        a.person = person
                        a.personVoiceId = (kind == .email || kind == .message) ? (replyingTo?.speakerId ?? "") : ""
                        a.allDay = allDay; a.repeatsYearly = yearly; a.durationMinutes = minutes
                        switch kind {
                        case .email, .message: a.detail = person.map { "To \($0)" } ?? ""
                        case .waiting:
                            a.person = speaker; a.personVoiceId = chunk.speakerId
                            a.detail = "\(speaker ?? "Another voice") said they would"
                        default: break
                        }
                        if remindedBy { a.detail = "Reminded by \(speaker ?? "someone")"; a.person = speaker; a.personVoiceId = chunk.speakerId }
                        // "Transfer it": say what "it" is
                        if a.detail.isEmpty, let prev = previous?.transcript, title.range(of: #"\b(?:it|that|those|them|this)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
                            a.detail = "After: “\(String(AnswerExtractor.split(prev).last ?? prev).prefix(90))”"
                        }
                        out.append(a)
                    }
                } else if let ask = ActionClassifier.request(in: sentence) {
                    if isMine && myVoice != nil {
                        var a = timed(item(.waiting, ask), when)
                        a.person = replyingTo.flatMap { voiceName($0.speakerId) }
                        a.personVoiceId = replyingTo?.speakerId ?? ""
                        a.detail = "You asked \(a.person ?? "them")"
                        out.append(a)
                    } else {
                        let kind = ActionClassifier.kind(ofCommitment: ask, when: when)
                        var a = timed(item(kind == .call || kind == .calendar ? .todo : kind, ask), when)
                        a.person = speaker
                        a.personVoiceId = chunk.speakerId
                        a.detail = "Asked by \(speaker ?? "someone")"
                        out.append(a)
                    }
                } else if case let items = ActionClassifier.shoppingItems(in: sentence), !items.isEmpty {
                    var a = item(.shopping, "Shopping list")
                    a.items = items
                    a.detail = "\(items.count) items"
                    out.append(a)
                } else if let ev = ActionClassifier.event(in: sentence, when: when) {
                    var a = timed(item(.calendar, ev.title), when)
                    a.allDay = ev.allDay; a.repeatsYearly = ev.repeatsYearly; a.durationMinutes = ev.minutes
                    out.append(a)
                }
            }
        }
        return dropEchoes(mergePickups(out))
    }

    private static func replacingMe(in title: String, with name: String) -> String {
        title.replacingOccurrences(of: #"\bme\b"#, with: name, options: .regularExpression)
    }

    private static let weakWords: Set<String> = ["send", "will", "that", "this", "with", "from", "about", "have", "them", "those", "please", "remember", "forget", "bring", "make", "sure"]
    private static func contentWords(_ s: String) -> Set<String> {
        Set(s.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init).filter { $0.count >= 4 && !weakWords.contains($0) })
    }

    /// When someone reminds the wearer of something the wearer promised a moment later ("don't forget to send me the recipe" … "I will send the
    /// recipe this evening"), it is one action, not two: the wearer's own promise stays and notes who asked.
    private static func dropEchoes(_ items: [ActionItem]) -> [ActionItem] {
        var out = items
        for asked in items where asked.detail.hasPrefix("Asked by") || asked.detail.hasPrefix("Reminded by") {
            guard let k = out.firstIndex(where: { $0.id != asked.id && !($0.detail.hasPrefix("Asked by") || $0.detail.hasPrefix("Reminded by")) && $0.dayId == asked.dayId
                && $0.speakerId != asked.speakerId && abs($0.wallStart - asked.wallStart) <= 150
                && contentWords($0.title).intersection(contentWords(asked.title)).count >= 2 }) else { continue }
            let who = asked.detail.replacingOccurrences(of: "Asked by ", with: "").replacingOccurrences(of: "Reminded by ", with: "")
            out[k].detail = out[k].detail.isEmpty ? "Asked by \(who)" : out[k].detail + " · asked by \(who)"
            out.removeAll { $0.id == asked.id }
        }
        return out
    }

    // MARK: Helpers

    private static func polish(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        t = t.prefix(1).uppercased() + t.dropFirst()
        if let last = t.last, !".!?".contains(last) { t += "." }
        return t
    }

    /// When the sentence was said: its day, at the time of day it was said. Relative days ("tomorrow") count from here.
    private static func referenceDate(for chunk: ChunkRecord, now: Date, calendar: Calendar) -> Date {
        let day = DayID.date(of: chunk.dayId, calendar: calendar) ?? calendar.startOfDay(for: now)
        return day.addingTimeInterval(chunk.wallStart)
    }

    /// "I will order the book tonight and look up workshops this weekend": two promises when each half has its own time.
    private static func compound(_ clause: String, reference: Date, calendar: Calendar) -> [(text: String, when: EventWhen?)] {
        let halves = clause.components(separatedBy: " and ")
        if halves.count == 2, halves[0].split(separator: " ").count >= 3, halves[1].split(separator: " ").count >= 3,
           let right = EventTime.find(in: halves[1], reference: reference, calendar: calendar) {
            let left = EventTime.find(in: halves[0], reference: reference, calendar: calendar)
            return [(halves[0], left), (halves[1].prefix(1).uppercased() + halves[1].dropFirst(), right)]
        }
        return [(clause, nil)]
    }

    /// The person being spoken to: the name the wearer used most recently in the last few minutes ("That sounds amazing, Priya").
    private static func promisesAddressee(before i: Int, in stored: [ChunkRecord], myVoice: String?, userName: String) -> String? {
        guard myVoice != nil else { return nil }   // until the phone knows which voice is the wearer's, it cannot tell who is being spoken to
        var j = i
        while j >= 0, stored[i].dayId == stored[j].dayId, stored[i].wallStart - stored[j].wallStart <= 180 {
            let spokenByMe = myVoice == nil || stored[j].speakerId.isEmpty || stored[j].speakerId == myVoice
            if spokenByMe, let name = TextNormalizer.personNames(in: stored[j].transcript ?? "").first(where: { !ProfileLogic.isSamePerson($0.name, as: userName) }) { return name.name }
            j -= 1
        }
        return nil
    }

    /// A name mentioned recently by someone else ("See Doctor Patel"), for "call her office".
    private static func recentOtherName(before i: Int, in stored: [ChunkRecord], excluding: String?, userName: String) -> String? {
        var j = i
        while j >= 0, stored[i].dayId == stored[j].dayId, stored[i].wallStart - stored[j].wallStart <= 120 {
            let hit = TextNormalizer.personNames(in: stored[j].transcript ?? "").last {
                !ProfileLogic.isSamePerson($0.name, as: userName) && $0.name.caseInsensitiveCompare(excluding ?? "") != .orderedSame
            }
            if let hit { return hit.name }
            j -= 1
        }
        return nil
    }

    /// "I will pick those up on my way home" belongs to the shopping list just before it: the list takes its time and the to-do goes.
    private static func mergePickups(_ items: [ActionItem]) -> [ActionItem] {
        let pickup = try! NSRegularExpression(pattern: #"\b(?:pick|get|buy|grab)\b.*\b(?:those|them|these|it)\b"#, options: .caseInsensitive)
        var out: [ActionItem] = []
        for item in items {
            if item.kind == .todo, pickup.firstMatch(in: item.title, range: NSRange(item.title.startIndex..., in: item.title)) != nil,
               let k = out.lastIndex(where: { $0.kind == .shopping && $0.dayId == item.dayId && item.wallStart - $0.wallStart <= 90 && $0.due == nil }) {
                out[k].due = item.due; out[k].dueText = item.dueText; out[k].hasClock = item.hasClock
                out[k].detail = "\(out[k].items.count) items" + (item.dueText.map { " · \($0)" } ?? "")
                continue
            }
            out.append(item)
        }
        return out
    }
}
