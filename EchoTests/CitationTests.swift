import Foundation
import Testing
@testable import Echo

/// Citations: Muse cites a snippet by label, and the phone maps the label back to its own audio.
@MainActor
struct CitationTests {
    // MARK: Parsing, old and new

    @Test func aReplyWithoutSourcesOrFollowUpsStillParses() {
        let old = #"{"answer":"You made promises.","items":[{"title":"Send the spec","detail":"To Ravi","when":"Wednesday noon","source_time":"09:05"}]}"#
        let parsed = CloudAnswer.parse(old)
        #expect(parsed.items.first?.sourceTime == "09:05")
        #expect(parsed.items.first?.source == "" && parsed.followUps.isEmpty)
    }

    @Test func aReplyWithSourcesAndFollowUpsKeepsThem() {
        let json = #"{"answer":"Two promises.","items":[{"title":"Send the spec","detail":"d","when":"","source":"S4","source_time":"09:05"}],"follow_ups":["Who else did I promise?","What is due first?"]}"#
        let parsed = CloudAnswer.parse(json)
        #expect(parsed.items.first?.source == "S4")
        #expect(parsed.followUps == ["Who else did I promise?", "What is due first?"])
    }

    @Test func aDigestSavedBeforeSourcesExistedStillLoads() throws {
        let old = #"{"day_summary":"A day.","conversations":[],"action_items":[{"what":"Send it","to_whom":"Ravi","due":"Friday","source_time":"09:05"}],"people":[]}"#
        let digest = try #require(DayDigest.parse(old))
        #expect(digest.actionItems.first?.source == "")
        let new = #"{"day_summary":"A day.","conversations":[],"action_items":[{"what":"Send it","to_whom":"Ravi","due":"Friday","source":"S2","source_time":"09:05"}],"people":[]}"#
        #expect(DayDigest.parse(new)?.actionItems.first?.source == "S2")
    }

    @Test func theSchemasAskForSourcesAndFollowUps() {
        #expect(EchoSchemas.answer.contains("\"source\"") && EchoSchemas.answer.contains("follow_ups"))
        #expect(EchoSchemas.digest.contains("\"source\""))
    }

    // MARK: The request

    @Test func theRequestLabelsSnippetsInOrderAndStillCarriesNoLocalIdentifiers() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let q = "What did I promise people today?"
        let outcome = await h.retriever.search(q)
        let plan = TierTwoPlanner.plan(query: q, decision: Router.route(query: q, outcome: outcome), outcome: outcome,
                                       chunks: h.chunks, model: "muse-spark-1.3")
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        #expect(plan.snippets.count >= 8)
        for (i, snippet) in plan.snippets.enumerated() {
            #expect(body.contains("S\(i + 1) \(snippet.time) — \(snippet.text)"), "snippet \(i + 1) is labelled with its own time and text")
        }
        #expect(!body.contains("S\(plan.snippets.count + 1) "), "no label beyond the last snippet")
        for chunk in h.chunks { #expect(!body.contains(chunk.id), "chunk id leaked") }
    }

    @Test func theDigestRequestLabelsEverySnippetAcrossConversations() async throws {
        let h = try await Harness.make()
        defer { h.cleanup() }
        let plan = TierTwoPlanner.digestPlan(chunks: h.chunks, model: "muse-spark-1.3")
        let body = String(decoding: try plan.request.bodyData(), as: UTF8.self)
        for i in 1...plan.snippets.count { #expect(body.contains("S\(i) "), "S\(i) missing") }
        #expect(body.contains("Conversation starting"))
    }

    // MARK: Resolving a citation

    private func chunk(_ id: String, at wall: Double, _ text: String) -> ChunkRecord {
        ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 5, peakDb: -10, meanDb: -30,
                    audioFile: "\(id).m4a", status: .stored, speechConfidence: 0.9, confirmedSeconds: 5, transcript: text)
    }

    @Test func aLabelResolvesToThatSnippetEvenWhenTimesCollide() {
        let a = chunk("a", at: 32_700, "I will send you the specification")
        let b = chunk("b", at: 32_710, "I will review the design document")
        let snippets = [Snippet(time: "09:05", text: a.transcript!, chunkID: "a"), Snippet(time: "09:05", text: b.transcript!, chunkID: "b")]
        #expect(CitationResolver.resolve(source: "S2", sourceTime: "09:05", detail: "", snippets: snippets, chunks: [a, b])?.id == "b")
        #expect(CitationResolver.resolve(source: "s1", sourceTime: "09:05", detail: "", snippets: snippets, chunks: [a, b])?.id == "a")
        #expect(CitationResolver.ordinal(of: "S12") == 12 && CitationResolver.ordinal(of: "12") == 12 && CitationResolver.ordinal(of: "x") == nil)
    }

    @Test func withoutALabelTheTimeResolvesWhenItIsUnique() {
        let a = chunk("a", at: 32_700, "I will send you the specification")
        let b = chunk("b", at: 45_000, "I will text you the link")
        #expect(CitationResolver.resolve(source: "", sourceTime: DemoClock.format(45_000), detail: "", snippets: [], chunks: [a, b])?.id == "b")
        #expect(CitationResolver.resolve(source: "", sourceTime: "23:59", detail: "", snippets: [], chunks: [a, b]) == nil)
    }

    @Test func withoutALabelASharedMinuteIsBrokenByTheWordsOfTheCitation() {
        let a = chunk("a", at: 32_700, "I will send you the API specification by Wednesday noon")
        let b = chunk("b", at: 32_712, "I will review the design document on Tuesday")
        let label = DemoClock.format(32_700)
        #expect(CitationResolver.resolve(source: "", sourceTime: label, detail: "Review the design document", snippets: [], chunks: [a, b])?.id == "b")
        #expect(CitationResolver.resolve(source: "", sourceTime: label, detail: "Send the API specification", snippets: [], chunks: [a, b])?.id == "a")
    }

    @Test func aBogusLabelFallsBackToTheTime() {
        let a = chunk("a", at: 32_700, "I will send you the specification")
        let snippets = [Snippet(time: "09:05", text: a.transcript!, chunkID: "a")]
        #expect(CitationResolver.resolve(source: "S9", sourceTime: "09:05", detail: "", snippets: snippets, chunks: [a])?.id == "a")
    }

    // MARK: Follow-ups

    @Test func followUpsNeverRepeatTheQuestionAndAreCapped() {
        let answer = CloudAnswer(answer: "x", followUps: ["What did I promise people today?", "Who is Ravi?", "who is ravi", "", "When is the plumber coming?", "A fourth one?"])
        let out = FollowUps.cloud(answer, asked: "what did i promise people today")
        #expect(out == ["Who is Ravi?", "When is the plumber coming?", "A fourth one?"])
    }

    @Test func withoutSuggestionsTheBroadQuestionsAreOfferedMinusTheOneAsked() {
        #expect(FollowUps.cloud(CloudAnswer(answer: "x"), asked: "Summarize my day") == ["What did I promise people today?"])
        #expect(FollowUps.cloud(CloudAnswer(answer: "x"), asked: "anything") == FollowUps.broad)
    }

    @Test func aLocalAnswerSuggestsMoreAboutThePersonOrTopic() {
        let person = FollowUps.local(query: "Where is Priya going in March?", terms: ["priya", "march"])
        #expect(person.first == "What else did Priya say?" && person.count == 3)
        let topic = FollowUps.local(query: "When is the plumber coming?", terms: ["plumber", "come"])
        #expect(topic.first == "What else did I hear about plumber?")
        let broad = FollowUps.local(query: "Summarize my day", terms: [])
        #expect(broad == ["What did I promise people today?"])
    }
}
