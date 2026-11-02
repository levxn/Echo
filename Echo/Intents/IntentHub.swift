import Foundation

/// How Siri and Shortcuts reach Echo's memory. While the app is open it registers its own live models here, so a spoken
/// question shows up in the app's history and ledger like any other. When Siri starts the app cold there is no screen, so
/// the same pieces are built without one (and a question that would need Muse is not sent, because nobody can review it).
@MainActor
final class IntentHub {
    static let shared = IntentHub()

    /// Supplied by the running app.
    var ask: ((String) async -> WatchAnswer)?
    var forget: ((Int) async -> Int)?
    var promises: (() async -> String)?

    private var headlessStore: ChunkStore?

    private func store() -> ChunkStore {
        if let headlessStore { return headlessStore }
        let s = ChunkStore()
        headlessStore = s
        return s
    }

    func answer(_ question: String) async -> WatchAnswer {
        if let ask { return await ask(question) }
        let store = store()
        let ledger = LedgerModel(store: store)
        await ledger.reload()
        let model = AskModel(store: store, ledger: ledger, client: MuseClientFactory.make())
        model.history = AskHistoryModel(store: store)
        model.brain = SystemLocalBrain()
        model.preferOnDevice = { UserDefaults.standard.bool(forKey: OnDevicePreference.key) }
        model.headless = true
        var reply = await model.quickAnswer(question, via: .typed)
        if reply.text.hasPrefix("Not sent.") { reply.text = "That needs Muse, and you review what is sent first. Open Echo to ask it." }
        return reply
    }

    func promisesToday() async -> String {
        if let promises { return await promises() }
        let store = store()
        let voices = VoiceBookModel(store: store)
        await voices.load()
        let done = Set((UserDefaults.standard.string(forKey: DayWiper.promiseDoneKey) ?? "").split(separator: "\n").map(String.init))
        return IntentAnswers.promises(chunks: await store.all(), userName: ProfileStore().name, myVoice: voices.me?.id, done: done, today: DayID.today())
    }

    func forgetRecent(minutes: Int) async -> Int {
        if let forget { return await forget(minutes) }
        let model = PipelineModel(store: store())
        await model.load()
        let gone = await model.forgetLast(minutes: minutes)
        Reminders().cancel(forChunkIDs: gone)
        return gone.count
    }
}
