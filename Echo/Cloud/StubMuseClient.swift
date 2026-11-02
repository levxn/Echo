import Foundation

/// Offline stand-in used **only when no API key exists** (or with `-stub`). Always labeled "Stub" in the UI
/// and the ledger. Its answers are canned for the demo day; it never pretends to be Muse.
struct StubMuseClient: MuseClient {
    var isStub: Bool { true }

    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        try await Task.sleep(for: .milliseconds(700))
        let content: String
        switch request.schemaName {
        case EchoSchemas.digestName: content = Self.digest
        case EchoSchemas.draftName: content = Self.draft
        case EchoSchemas.journalName: content = Self.journal
        default: content = Self.answer(for: request.user)
        }
        return MuseResponse(content: content, model: "stub", promptTokens: 0, completionTokens: 0,
                            latencyMs: 700, isStub: true)
    }

    private static func answer(for user: String) -> String {
        let q = user.lowercased()
        let result: CloudAnswer
        if q.contains("promis") || q.contains("commit") || q.contains("to-do") || q.contains("tomorrow") {
            result = CloudAnswer(answer: "Stub preview: you made about nine commitments across four conversations, most of them for the next couple of days.", items: [
                CloudItem(title: "Send the API spec to Ravi", detail: "Promised as a firm commitment.", when: "Wednesday noon", sourceTime: "09:05"),
                CloudItem(title: "Review the design document", detail: "Leave comments before the end of the day.", when: "Tuesday", sourceTime: "09:05"),
                CloudItem(title: "Call the doctor's office", detail: "Book an appointment for your tooth.", when: "Tomorrow morning", sourceTime: "12:30"),
                CloudItem(title: "Send the lentil soup recipe", detail: "Promised to Priya.", when: "This evening", sourceTime: "12:30"),
                CloudItem(title: "Answer the landlord about renewing", detail: "Final answer on the 4% rent increase.", when: "Before November 20", sourceTime: "15:10"),
                CloudItem(title: "Transfer this month's rent", detail: "Outstanding rent for the apartment.", when: "Tomorrow", sourceTime: "15:10"),
                CloudItem(title: "Call Grandma", detail: "Promised to call.", when: "Sunday afternoon", sourceTime: "18:40"),
            ], followUps: ["What did Mister Brennan say about the lease?", "Summarize my day"])
        } else {
            result = CloudAnswer(answer: "Stub preview: four conversations today. A morning stand-up about the billing service launch, lunch with Priya about a Lisbon trip, a call with the landlord about a plumber and the lease, and a family dinner planning a birthday weekend.", items: [],
                                 followUps: ["What did I promise people today?", "When is the plumber coming?"])
        }
        return (try? String(data: JSONEncoder().encode(result), encoding: .utf8)) ?? ""
    }

    private static let draft = (try? String(data: JSONEncoder().encode(MessageDraft(
        subject: "About what I promised",
        body: "Stub preview: Hi, I wanted to follow up on what I promised. I'll get it to you as soon as I can, and I'll let you know the moment it's done.")), encoding: .utf8)) ?? ""

    private static let journal = (try? String(data: JSONEncoder().encode(JournalEntry(
        title: "A full day (stub preview)",
        entry: "Stub preview: a busy day with a stand-up about the billing service, lunch with Priya planning a trip, a call about the plumber and the lease, and a family dinner. I promised a few things I want to follow through on.",
        highlights: ["Billing service ships Thursday", "Trip to Lisbon in March", "Plumber on Friday at ten"])), encoding: .utf8)) ?? ""

    private static let digest: String = {
        let digest = DayDigest(
            daySummary: "Stub preview: a stand-up about shipping the billing service, lunch planning a Lisbon trip, a landlord call about a plumber and a lease renewal, and a family dinner planning a birthday weekend.",
            conversations: [
                DigestConversation(time: "09:05", title: "Morning stand-up", summary: "Billing service deploys Thursday; API spec due Wednesday noon."),
                DigestConversation(time: "12:30", title: "Lunch", summary: "Trip to Lisbon in March; birthday gift ideas."),
                DigestConversation(time: "15:10", title: "Landlord call", summary: "Plumber Friday at 10; lease renewal offer at +4%."),
                DigestConversation(time: "18:40", title: "Family dinner", summary: "Lake cabin weekend for Mom's birthday on November 14."),
            ],
            actionItems: [
                DigestAction(what: "Send the API spec", toWhom: "Ravi", due: "Wednesday noon", sourceTime: "09:05"),
                DigestAction(what: "Answer the lease renewal", toWhom: "Mr. Brennan", due: "Before November 20", sourceTime: "15:10"),
                DigestAction(what: "Call Grandma", toWhom: "Grandma", due: "Sunday afternoon", sourceTime: "18:40"),
            ],
            people: ["Maya", "Ravi", "Priya", "Mr. Brennan", "Mom", "Dad"])
        return (try? String(data: JSONEncoder().encode(digest), encoding: .utf8)) ?? ""
    }()
}
