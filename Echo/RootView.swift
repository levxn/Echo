import os
import SwiftUI

enum RootTab: String {
    case today, moments, ask, ledger

    /// Launch-argument values for `-tab`. The old name `pipeline` still opens Moments, so older scripts keep working.
    static func from(argument: String) -> RootTab? { argument == "pipeline" ? .moments : RootTab(rawValue: argument) }

    /// The title in the top bar.
    var title: String {
        switch self {
        case .today: "Today"
        case .moments: "Moments"
        case .ask: "Ask"
        case .ledger: "Privacy"
        }
    }
}

struct RootView: View {
    let model: PipelineModel
    let link: PhoneLink
    let voices: VoiceBookModel
    let privacy: RecordingPrivacy
    let watcher: PromiseWatcher

    @State private var ask: AskModel
    @State private var history: AskHistoryModel
    @State private var voice = VoiceAskModel()
    @State private var speaker = Speaker()
    @State private var reminders = Reminders()
    @State private var calendarLink = CalendarLink()
    @State private var ledger: LedgerModel
    @State private var digest: DigestModel
    @State private var player: ChunkPlayer
    @State private var today = TodayState()
    @State private var profile = ProfileStore()
    @State private var showProfile = ProcessInfo.processInfo.arguments.contains("-show-profile")
    @State private var tab: RootTab
    @State private var caption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PipelineModel, link: PhoneLink, voices: VoiceBookModel, privacy: RecordingPrivacy, watcher: PromiseWatcher) {
        self.watcher = watcher
        self.model = model
        self.link = link
        self.voices = voices
        self.privacy = privacy
        let ledger = LedgerModel(store: model.store)
        _ledger = State(initialValue: ledger)
        let client = MuseClientFactory.make()
        let askModel = AskModel(store: model.store, ledger: ledger, client: client)
        let history = AskHistoryModel(store: model.store)
        askModel.history = history
        _history = State(initialValue: history)
        _ask = State(initialValue: askModel)
        _digest = State(initialValue: DigestModel(store: model.store, ledger: ledger, client: client))
        let player = ChunkPlayer(directory: model.store.chunksDirectory)
        _player = State(initialValue: player)
        // Dev hook: `simctl launch ... -tab ask` opens a tab directly.
        let args = ProcessInfo.processInfo.arguments
        let requested = args.firstIndex(of: "-tab").flatMap { $0 + 1 < args.count ? RootTab.from(argument: args[$0 + 1]) : nil }
        _tab = State(initialValue: requested ?? .today)
    }

    /// One slim bar on every tab: profile, where you are, and the watch / cloud / on-this-phone indicators.
    private func topBar(_ tab: RootTab) -> some View {
        EchoTopBar(title: tab.title, profile: profile,
                   watch: HeaderStatus.watch(reachable: model.watchReachable, listening: model.session == .running),
                   cloud: HeaderStatus.cloud(enabled: ledger.cloudEnabled, reviewing: ledger.reviewBeforeSend),
                   listening: model.session == .running,
                   onProfile: { showProfile = true }, onWatch: { self.tab = .moments }, onCloud: { self.tab = .ledger })
    }

    /// Forgets the last `minutes` of what was heard, and everything that depended on it. Returns how many moments went.
    private func forgetRecent(minutes: Int) async -> Int {
        let gone = await model.forgetLast(minutes: minutes)
        guard !gone.isEmpty else { return 0 }
        reminders.cancel(forChunkIDs: gone)
        ask.clear()
        digest.reset()
        player.stop()
        await history.reload()
        return gone.count
    }

    /// Sets a reminder for a promise the watch (or a notification) just showed: at its due time, or in an hour.
    private func keepPromise(id: String) async -> Bool {
        guard let promise = PromiseExtractor.extract(from: model.chunks, userName: profile.name).first(where: { $0.id == id }),
              let option = ReminderOptions.options(due: promise.due, now: Date()).first else { return false }
        let ok = await reminders.schedule(promise, at: option.date)
        if ok { Haptics.success() }
        return ok
    }

    private func forgetDay(includeLedger: Bool) {
        Task {
            await DayWiper.forget(resetDay: { await model.reset() }, ask: ask, digest: digest, player: player,
                                  ledger: ledger, includeLedger: includeLedger, reminders: reminders, voices: voices, calendar: calendarLink)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.horizon.fill", value: RootTab.today) {
                TodayView(model: model, digest: digest, player: player, state: today, profile: profile,
                          onAsk: { question in
                              tab = .ask
                              Task { await ask.ask(question, via: .suggestion) }
                          })
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.today) }
            }
            Tab("Moments", systemImage: "waveform", value: RootTab.moments) {
                MomentsView(model: model, player: player, privacy: privacy) { ledger.showArchitecture = true }
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.moments) }
            }
            Tab("Ask", systemImage: "sparkles", value: RootTab.ask) {
                AskView(ask: ask, voice: voice, history: history, player: player, hasMemory: model.storedCount > 0, chunks: model.chunks,
                        onViewLedger: { tab = .ledger })
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.ask) }
            }
            Tab("Ledger", systemImage: "lock.shield.fill", value: RootTab.ledger) {
                LedgerView(ledger: ledger, model: model, history: history, privacy: privacy, onForgetRecent: { await forgetRecent(minutes: $0) }) { includeLedger in forgetDay(includeLedger: includeLedger) }
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.ledger) }
            }
        }
        .overlay(alignment: .bottom) {
            if let caption {
                DemoCaption(text: caption)
                    .transition(.echoRise(reduceMotion: reduceMotion))
                    .id(caption)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: caption)
        // "How Echo works" can be opened from Moments and from the Ledger, so the sheet lives here.
        .background { Color.clear.sheet(isPresented: Bindable(ledger).showArchitecture) { ArchitectureView(model: model, ledger: ledger) } }
        .background {
            Color.clear.sheet(isPresented: $showProfile) {
                ProfileSheet(profile: profile) { tab = .ledger }
            }
        }
        // "Review before sending": the request waits here until the user decides. Swiping the sheet away declines.
        .sheet(item: Binding(get: { ledger.gate.pending }, set: { if $0 == nil { ledger.gate.cancel() } })) { review in
            ReviewSheet(review: review, onSend: { ledger.gate.approve() }, onCancel: { ledger.gate.cancel() })
        }
        // A new watch day starts from nothing, and that clears the history too, so show what is really stored.
        .onChange(of: model.session) { Task { await history.reload() } }
        .environment(speaker)
        .environment(voices)
        .environment(privacy)
        .environment(reminders)
        .environment(calendarLink)
        .preferredColorScheme(.dark)
        .tint(Palette.teal)
        // Large text is fully supported up to the first accessibility size; beyond it these dense cards
        // would wrap mid-word, so the scale is capped there.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .task {
            // The language models load lazily; touching them now keeps the first question fast.
            let warm = Task.detached(priority: .utility) {
                _ = Embedder.vector(for: "warm up the plumber lease")
                _ = TextNormalizer.lemmas("warming up")
                _ = TextNormalizer.nameTokens(in: "Warm Up")
            }
            // Questions asked on the watch: answered here, shown here too, and logged like any other.
            ask.mySpeakerID = { voices.me?.id }
            link.requests = WatchRequests(
                transcriber: QuestionTranscriber(),
                answer: { question, via in
                    await warm.value
                    tab = .ask
                    let answer = await ask.quickAnswer(question, via: via)
                    Log.link.notice("watch ask: \(answer.source.rawValue) in \(answer.milliseconds) ms (\(via.rawValue))")
                    return answer
                },
                history: { history.recentForWatch() },
                speakVoiceAnswers: { profile.speakVoiceAnswers },
                forgetRecent: { await forgetRecent(minutes: $0) },
                keepPromise: { await keepPromise(id: $0) })
            // A promise just heard: the watch shows "Got it"; with no watch nearby it is a notification with a Remind me button.
            watcher.isEnabled = { profile.catchPromises }
            watcher.myVoice = { voices.me?.id }
            watcher.onCaught = { promise in
                if !link.sendPromiseCaught(promise) { Task { await reminders.scheduler.postCaught(id: promise.id, body: promise.sentence) } }
            }
            reminders.scheduler.onAction { _, id in Task { _ = await keepPromise(id: id) } }
            privacy.onAnnounceChanged = { link.sendSettings(announce: $0) }
            link.sendSettings(announce: privacy.announce)
            // Spoken answers and recorded moments take turns, and a voice question's answer is read back if the person wants.
            speaker.willSpeak = { player.stop() }
            player.willPlay = { speaker.stop() }
            voice.afterAnswer = { ask in
                if profile.speakVoiceAnswers, let text = ask.spokenAnswer { speaker.speak(text) }
            }
            await model.purgeExpired()
            // Dev hook: `-voice-me` says the voice heard most is the person's own, and names it after them (screenshots, the take).
            if ProcessInfo.processInfo.arguments.contains("-voice-me") {
                await voices.load()
                if let mine = voices.suggestedMe ?? voices.voices.first {
                    await voices.rename(mine.id, to: profile.name)
                    await voices.setMe(mine.id)
                }
            }
            // Dev hook: `-forget-recent N` forgets the last N minutes once the day has loaded (end-to-end checks).
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-forget-recent"), i + 1 < ProcessInfo.processInfo.arguments.count,
               let minutes = Int(ProcessInfo.processInfo.arguments[i + 1]) {
                await model.load()
                let n = await forgetRecent(minutes: minutes)
                Log.app.notice("forget-recent: \(n) moments")
            }
            await history.reload()
            await ledger.reload()
            await digest.load()
            let args = ProcessInfo.processInfo.arguments
            // Dev hooks for headless verification: `-ask "question"` and `-digest` run once the day has loaded,
            // and `-demo-script` performs the whole demo in one take (see DemoDriver).
            if DemoDriver.requested {
                await warm.value
                await model.load()
                await DemoDriver(model: model, ask: ask, ledger: ledger, digest: digest, voice: voice, history: history,
                                 today: today, player: player,
                                 startWatch: { link.sendDemoStart() },
                                 watchQuickAsk: { link.sendDemoQuickAsk($0) },
                                 watchVoiceAsk: { link.sendDemoVoiceAsk($0) },
                                 setTab: { tab = $0 },
                                 setCaption: { caption = $0 }).run()
            } else if let i = args.firstIndex(of: "-voice-ask"), i + 1 < args.count, let clip = Int(args[i + 1]) {
                // Asks recorded question N (1...5) by voice: the real recorder, on-device understanding, the real Ask flow.
                await warm.value
                await model.load()
                tab = .ask
                await voice.listen(clip: clip, ask: ask)
            } else if let i = args.firstIndex(of: "-ask"), i + 1 < args.count {
                await warm.value
                await model.load()
                tab = .ask
                await ask.ask(args[i + 1])
                // `-then "follow-up"` asks a second question straight after, to see a follow-up.
                if let j = args.firstIndex(of: "-then"), j + 1 < args.count { await ask.ask(args[j + 1]) }
            } else if args.contains("-digest") {
                await model.load()
                tab = .today
                await digest.generate(chunks: model.todayChunks)
            }
        }
    }
}
