import Foundation

/// JSON Schemas for Muse's structured output (no recursion, shallow depth, per Meta's limits).
enum EchoSchemas {
    static let answerName = "EchoAnswer"
    static let answer = """
    {"type":"object","properties":{
      "answer":{"type":"string","description":"A direct answer of at most three sentences, grounded only in the snippets."},
      "items":{"type":"array","items":{"type":"object","properties":{
        "title":{"type":"string","description":"Short label, e.g. what was promised"},
        "detail":{"type":"string","description":"One sentence of detail"},
        "when":{"type":"string","description":"Due date or time mentioned, or empty"},
        "source_time":{"type":"string","description":"HH:MM of the snippet this came from"}},
        "required":["title","detail","when","source_time"]}}},
      "required":["answer","items"]}
    """

    static let digestName = "EchoDigest"
    static let digest = """
    {"type":"object","properties":{
      "day_summary":{"type":"string","description":"Two to four sentences summarizing the day."},
      "conversations":{"type":"array","items":{"type":"object","properties":{
        "time":{"type":"string"},"title":{"type":"string"},"summary":{"type":"string"}},
        "required":["time","title","summary"]}},
      "action_items":{"type":"array","items":{"type":"object","properties":{
        "what":{"type":"string"},"to_whom":{"type":"string"},"due":{"type":"string"},"source_time":{"type":"string"}},
        "required":["what","to_whom","due","source_time"]}},
      "people":{"type":"array","items":{"type":"string"}}},
      "required":["day_summary","conversations","action_items","people"]}
    """
}

/// Models sometimes wrap structured output in a code fence or a sentence of prose. This pulls out the JSON object.
enum JSONExtract {
    static func object(in text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end else { return nil }
        return String(t[start...end])
    }
}

struct CloudItem: Codable, Identifiable, Equatable {
    let title: String
    let detail: String
    let when: String
    let sourceTime: String
    var id: String { "\(sourceTime)|\(title)" }

    enum CodingKeys: String, CodingKey { case title, detail, when, sourceTime = "source_time" }

    init(title: String, detail: String, when: String = "", sourceTime: String = "") {
        self.title = title; self.detail = detail; self.when = when; self.sourceTime = sourceTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        detail = try c.decodeIfPresent(String.self, forKey: .detail) ?? ""
        when = try c.decodeIfPresent(String.self, forKey: .when) ?? ""
        sourceTime = try c.decodeIfPresent(String.self, forKey: .sourceTime) ?? ""
    }
}

struct CloudAnswer: Codable, Equatable {
    let answer: String
    let items: [CloudItem]

    init(answer: String, items: [CloudItem] = []) { self.answer = answer; self.items = items }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = try c.decode(String.self, forKey: .answer)
        items = try c.decodeIfPresent([CloudItem].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey { case answer, items }

    /// Parses Muse's structured reply, tolerating a code fence or surrounding prose; if no JSON object can be
    /// read, shows the raw text rather than failing.
    static func parse(_ content: String) -> CloudAnswer {
        for candidate in [content, JSONExtract.object(in: content)].compactMap({ $0 }) {
            if let data = candidate.data(using: .utf8), let parsed = try? JSONDecoder().decode(CloudAnswer.self, from: data) {
                return parsed
            }
        }
        return CloudAnswer(answer: content.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct DigestConversation: Codable, Equatable, Identifiable {
    let time: String
    let title: String
    let summary: String
    var id: String { time + title }
}

struct DigestAction: Codable, Equatable, Identifiable {
    let what: String
    let toWhom: String
    let due: String
    let sourceTime: String
    var id: String { sourceTime + what }
    enum CodingKeys: String, CodingKey { case what, toWhom = "to_whom", due, sourceTime = "source_time" }
}

struct DayDigest: Codable, Equatable {
    let daySummary: String
    let conversations: [DigestConversation]
    let actionItems: [DigestAction]
    let people: [String]
    enum CodingKeys: String, CodingKey {
        case daySummary = "day_summary", conversations, actionItems = "action_items", people
    }

    static func parse(_ content: String) -> DayDigest? {
        for candidate in [content, JSONExtract.object(in: content)].compactMap({ $0 }) {
            if let digest = candidate.data(using: .utf8).flatMap({ try? JSONDecoder().decode(DayDigest.self, from: $0) }) {
                return digest
            }
        }
        return nil
    }
}
