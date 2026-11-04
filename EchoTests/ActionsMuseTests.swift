import Foundation
import Testing
@testable import Echo

private final class ScriptedActionsMuse: MuseClient {
    var isStub = false
    var content = #"{"actions":[]}"#
    var requests: [MuseRequest] = []
    func complete(_ request: MuseRequest) async throws -> MuseResponse {
        requests.append(request)
        return MuseResponse(content: content, model: "muse-spark-1.3", promptTokens: 5, completionTokens: 5, latencyMs: 2, isStub: isStub)
    }
}

private func moment(_ id: String, _ text: String, at wall: Double, day: String = DayID.today()) -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: .stored, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day)
}

@MainActor
struct ActionsMuseTests {
    private let secret = "tango seven dollar"
    private var day: [ChunkRecord] {
        let base = 36_000.0   // seconds since midnight, like the app
        return [
            moment("a", "My wifi password is \(secret) and my card number is 4111 1111 1111 1111", at: base),
            moment("b", "Ravi will send the cloud credits quote to Priya next week, my number is 415 555 0134", at: base + 30),
            moment("c", "We need eggs, olive oil and oranges from the shop", at: base + 60),
        ]
    }

    private func rig(cloud: Bool = true) async throws -> (ledger: LedgerModel, actions: ActionsModel, store: ChunkStore, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-musea-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        let defaults = UserDefaults(suiteName: "echo-musea-\(UUID().uuidString)")!
        let ledger = LedgerModel(store: store, defaults: defaults)
        ledger.cloudEnabled = cloud
        for c in day { await store.upsert(c) }
        return (ledger, ActionsModel(store: store), store, dir)
    }

    @Test func theRequestCarriesPlaceholdersAndNeverTheSecrets() {
        let plan = TierTwoPlanner.actionsPlan(chunks: day, day: DayID.today(), model: "muse-spark-1.3")
        let sent = plan.request.developer + plan.request.user + plan.snippets.map(\.text).joined()
        for value in [secret, "4111 1111 1111 1111", "415 555 0134"] { #expect(!sent.contains(value), "\(value) must not leave the phone") }
        #expect(plan.heldBackCount >= 3 && plan.canCall && plan.snippets.count == 3)
        #expect(plan.request.user.contains("S1") && plan.request.schemaName == EchoSchemas.actionsName)
        #expect(sent.contains("[PASSWORD_1]") || sent.contains("[CARD_1]"))
    }

    @Test func whatMuseFindsIsCheckedAgainstTheRealMoments() throws {
        let plan = TierTwoPlanner.actionsPlan(chunks: day, day: DayID.today(), model: "m")
        let list = try #require(MuseActionList.parse("""
        ```json
        {"actions":[
         {"title":"check the cloud credits quote","kind":"waiting","person":"Ravi","when":"next week","detail":"Ravi owes a quote","items":[],"source":"S2"},
         {"title":"buy groceries","kind":"shopping","person":"","when":"","detail":"","items":["Eggs","Olive oil","Oranges"],"source":"S3"},
         {"title":"Invented task","kind":"todo","person":"","when":"","detail":"","items":[],"source":"S9"},
         {"title":"x","kind":"todo","person":"","when":"","detail":"","items":[],"source":"S1"}]}
        ```
        """))
        let items = MuseActionMapper.items(from: list, snippets: plan.snippets, chunks: day, masking: plan.masking, now: Date())
        #expect(items.map(\.id) == ["b#m0", "c#m0"], "an unknown source and a too-short title are dropped")
        #expect(items[0].kind == .waiting && items[0].person == "Ravi" && items[0].origin == .muse && items[0].title == "Check the cloud credits quote")
        #expect(items[1].kind == .shopping && items[1].items == ["Eggs", "Olive oil", "Oranges"])
        #expect(items[0].quote.contains("[PHONE_1]") == false || !items[0].quote.contains("415"), "the stored quote is the phone's own text")
        #expect(MuseActionList.parse("nonsense") == nil)
    }

    @Test func findingMoreGoesThroughTheLedgerAndMergesWithoutDuplicates() async throws {
        let r = try await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        let client = ScriptedActionsMuse()
        client.content = """
        {"actions":[{"title":"Change the wifi password","kind":"todo","person":"","when":"","detail":"","items":[],"source":"S1"}]}
        """
        let muse = MuseActionsModel(ledger: r.ledger, client: client)
        let added = await muse.find(chunks: day, day: DayID.today(), actions: r.actions, userName: "Levin", myVoice: nil, voiceNames: [:])
        #expect(added == 1 && muse.state == .done(found: 1, isStub: false))
        #expect(r.actions.items.contains { $0.id == "a#m0" })
        #expect(client.requests.count == 1 && !(client.requests[0].user + client.requests[0].developer).contains(secret))
        let entry = try #require(r.ledger.entries.first)
        #expect(entry.kind == .actions && entry.leftDevice && entry.heldBackCount >= 3 && !entry.snippets.map(\.text).joined().contains("4111"))
        // asking again finds the same thing: it is not listed twice
        let again = await muse.find(chunks: day, day: DayID.today(), actions: r.actions, userName: "Levin", myVoice: nil, voiceNames: [:])
        #expect(again == 0 && r.actions.items.filter { $0.id == "a#m0" }.count == 1)
    }

    @Test func nothingIsSentWhenMuseIsOffAndTheStubInventsNothing() async throws {
        let r = try await rig(cloud: false); defer { try? FileManager.default.removeItem(at: r.dir) }
        let client = ScriptedActionsMuse()
        let muse = MuseActionsModel(ledger: r.ledger, client: client)
        #expect(await muse.find(chunks: day, day: DayID.today(), actions: r.actions, userName: "L", myVoice: nil, voiceNames: [:]) == 0)
        #expect(muse.state == .cloudOff && client.requests.isEmpty)
        let stub = try await StubMuseClient().complete(MuseRequest(model: "m", developer: "", user: "x", schemaName: EchoSchemas.actionsName, schemaJSON: EchoSchemas.actions))
        #expect(stub.isStub && MuseActionList.parse(stub.content)?.actions.isEmpty == true)
    }

    @Test func aDraftRequestForAnActionKeepsSecretsOnThePhoneAndTheyComeBackInTheDraft() throws {
        let item = ActionItem(id: "a#a0", kind: .message, title: "Send Priya the wifi password", person: "Priya", quote: "q", chunkID: "a", dayId: DayID.today(), wallStart: day[0].wallStart, timeLabel: "09:00")
        let plan = TierTwoPlanner.draftPlan(promise: item.asPromise, chunks: day, tone: .friendly, channel: .text, model: "m",
                                            instruction: "Write a warm text message to Priya that keeps this promise: “\(item.title)”.")
        let sent = plan.request.developer + plan.request.user
        #expect(!sent.contains(secret) && !sent.contains("4111") && sent.contains("Priya") && sent.contains("keeps this promise"))
        #expect(plan.heldBackCount >= 1)
        // Muse writes with the placeholder; on the phone the real value goes back in
        let placeholder = try #require(plan.masking.secrets.entries.first { $0.original.contains("tango") }?.token)
        let written = MessageDraft(subject: "", body: "Hi Priya, the wifi password is \(placeholder).")
        #expect(written.restoredOnPhone(plan.masking).body.contains(secret))
        #expect(!written.restored(plan.masking).body.contains(secret), "the plain restore used for answers leaves it as a placeholder")
    }
}
