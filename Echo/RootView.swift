import os
import SwiftUI

enum RootTab: String {
    case today, actions, moments, ask, ledger

    /// Launch-argument values for `-tab`. The old name `pipeline` still opens Moments, so older scripts keep working.
    static func from(argument: String) -> RootTab? { argument == "pipeline" ? .moments : RootTab(rawValue: argument) }

    /// The title in the top bar.
    var title: String {
        switch self {
        case .today: "Today"
        case .actions: "Actions"
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
    let places: PlacesModel

    @State private var ask: AskModel
    @State private var history: AskHistoryModel
    @State private var voice = VoiceAskModel()
    @State private var speaker = Speaker()
    @State private var reminders: Reminders
    @State private var briefings: BriefingCenter
    @State private var calendarLink = CalendarLink()
    @State private var ledger: LedgerModel
    @State private var digest: DigestModel
    @State private var drafts: DraftModel
    @State private var journal: JournalModel
    @State private var actions: ActionsModel
    @State private var museActions: MuseActionsModel
    @State private var performer: ActionPerformer
    @State private var player: ChunkPlayer
    @State private var today = TodayState()
    @State private var profile = ProfileStore()
    @State private var showProfile = ProcessInfo.processInfo.arguments.contains("-show-profile")
    @State private var tab: RootTab
    @State private var caption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PipelineModel, link: PhoneLink, voices: VoiceBookModel, privacy: RecordingPrivacy, watcher: PromiseWatcher, places: PlacesModel) {
        self.watcher = watcher
        self.places = places
        self.model = model
        self.link = link
        self.voices = voices
        let reminders = Reminders()
        _reminders = State(initialValue: reminders)
        _briefings = State(initialValue: BriefingCenter(scheduler: reminders.scheduler))
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
        _drafts = State(initialValue: DraftModel(ledger: ledger, client: client))
        _journal = State(initialValue: JournalModel(store: model.store, ledger: ledger, client: client))
        let actionsModel = ActionsModel(store: model.store)
        _actions = State(initialValue: actionsModel)
        _museActions = State(initialValue: MuseActionsModel(ledger: ledger, client: client))
        let calendar = SystemCalendar()
        _performer = State(initialValue: ActionPerformer(model: actionsModel, events: calendar, reminders: SystemReminders(), notifier: reminders, contacts: SystemContacts(),
                                                         canSendMail: { ComposerSupport.canSendMail }, canSendText: { ComposerSupport.canSendText }))
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
        await refreshActions()
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

    /// Says the voice heard most is the person's own, and names it after them.
    private func introduceVoice() async {
        await voices.load()
        if let mine = voices.suggestedMe ?? voices.voices.first {
            // Marking "me" saves every voice, so it goes first: the rename must be the last write.
            await voices.setMe(mine.id)
            await voices.rename(mine.id, to: profile.name)
        }
        await voices.load()   // the app's own load may have finished with an older list in between
    }

    /// Gives the demo day's places their names.
    private func introducePlaces() async {
        await model.load()
        await places.load()
        let known: [(String, Coordinate)] = [("The office", .init(lat: 12.9716, lon: 77.5946)), ("The café", .init(lat: 12.9352, lon: 77.6245)),
                                             ("Home", .init(lat: 12.9784, lon: 77.6408)), ("The clinic", .init(lat: 12.9279, lon: 77.6271))]
        for cluster in PlaceLogic.clusters(from: model.chunks, places: places.places) where cluster.place == nil {
            if let match = known.first(where: { $0.1.distance(to: cluster.coordinate) < 300 }) { await places.name(cluster, as: match.0) }
        }
    }

    /// Finds what was said that is worth acting on, again, from what is stored now.
    private func refreshActions() async {
        await actions.refresh(chunks: model.chunks, userName: profile.name, myVoice: voices.me?.id,
                              voiceNames: voices.nameMap)
        await reminders.setMorningActions(enabled: profile.actionsMorning, count: actions.pendingCount)
    }

    /// Re-plans the briefings for meetings in the next day (when the person has turned them on).
    private func refreshBriefings() async {
        guard briefings.enabled else {
            await briefings.refresh(people: [], briefing: { _ in Briefing(person: "", lastTime: nil, youOwe: [], theyOwe: [], topics: [], moments: 0) })
            return
        }
        let chunks = model.chunks, name = profile.name
        let people = await Task.detached(priority: .utility) { PeopleIndex.build(from: chunks, userName: name) }.value
        let promises = PromiseExtractor.extract(from: chunks)
        let done = Set((UserDefaults.standard.string(forKey: DayWiper.promiseDoneKey) ?? "").split(separator: "\n").map(String.init))
        await briefings.refresh(people: people, briefing: { person in
            BriefingBuilder.make(for: person, chunks: chunks, promises: promises, done: done, myVoice: voices.me?.id,
                                 voiceNamed: { n in voices.voices.first { ($0.name ?? "").lowercased() == n.lowercased() }?.id }, now: model.now())
        })
        Log.app.notice("briefings: \(briefings.planned.count) planned")
    }

    private func forgetDay(includeLedger: Bool) {
        Task {
            await DayWiper.forget(resetDay: { await model.reset() }, ask: ask, digest: digest, player: player,
                                  ledger: ledger, includeLedger: includeLedger, reminders: reminders, voices: voices, calendar: calendarLink, journal: journal, briefings: briefings, actions: actions)
        }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.horizon.fill", value: RootTab.today) {
                TodayView(model: model, digest: digest, player: player, state: today, profile: profile, journal: journal,
                          onAsk: { question in
                              tab = .ask
                              Task { await ask.ask(question, via: .suggestion) }
                          })
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.today) }
            }
            Tab("Actions", systemImage: "checklist", value: RootTab.actions) {
                ActionsView(model: model, player: player)
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.actions) }
            }
            .badge(actions.pendingCount)
            Tab("Moments", systemImage: "waveform", value: RootTab.moments) {
                MomentsView(model: model, player: player, privacy: privacy) { ledger.showArchitecture = true }
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.moments) }
            }
            Tab("Ask", systemImage: "text.bubble.fill", value: RootTab.ask) {
                AskView(ask: ask, voice: voice, history: history, player: player, hasMemory: model.storedCount > 0, chunks: model.chunks,
                        onViewLedger: { tab = .ledger })
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.ask) }
            }
            Tab("Ledger", systemImage: "lock.shield.fill", value: RootTab.ledger) {
                LedgerView(ledger: ledger, model: model, history: history, privacy: privacy, onForgetRecent: { await forgetRecent(minutes: $0) }) { includeLedger in forgetDay(includeLedger: includeLedger) }
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.ledger) }
            }
        }
    }

    var body: some View {
        withTasks(withSheets(withOverlay(tabs)))
            .modifier(FirstImpression())
            .modifier(WidgetSync(model: model, reminders: reminders, profile: profile, voices: voices, link: link))
            .modifier(ModelEnvironment(speaker: speaker, voices: voices, privacy: privacy, reminders: reminders, calendar: calendarLink, drafts: drafts, ledger: ledger, briefings: briefings, places: places, actions: actions, museActions: museActions, performer: performer))
            .preferredColorScheme(.dark)
            .tint(Palette.teal)
            // Large text is fully supported up to the first accessibility size; beyond it these dense cards
            // would wrap mid-word, so the scale is capped there.
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)
            .task { await start() }
    }

    private func withOverlay(_ content: some View) -> some View {
        content
            .overlay(alignment: .bottom) {
                // `-no-caption-overlay`: the recording draws the captions itself, under the phone and the watch.
                if let caption, !ProcessInfo.processInfo.arguments.contains("-no-caption-overlay") {
                    DemoCaption(text: caption)
                        .transition(.echoRise(reduceMotion: reduceMotion))
                        .id(caption)
                }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: caption)
    }

    private func withSheets(_ content: some View) -> some View {
        content
            // "How Echo works" can be opened from Moments and from the Ledger, so the sheet lives here.
            .background { Color.clear.sheet(isPresented: Bindable(ledger).showArchitecture) { ArchitectureView(model: model, ledger: ledger) } }
            .background {
                Color.clear.sheet(isPresented: $showProfile) {
                    ProfileSheet(profile: profile) { tab = .ledger }
                }
            }
            // "Review before sending": the request waits here until the user decides. Swiping the sheet away declines.
            // (A draft's review is shown inside the draft sheet, because a sheet can't open over another from here.)
            .sheet(item: Binding(get: { ledger.gate.pending.flatMap { $0.kind == .draft ? nil : $0 } },
                                 set: { if $0 == nil, ledger.gate.pending?.kind != .draft { ledger.gate.cancel() } })) { review in
                ReviewSheet(review: review, onSend: { ledger.gate.approve() }, onCancel: { ledger.gate.cancel() })
            }
    }

    private func withTasks(_ content: some View) -> some View {
        content
            // A new watch day starts from nothing, and that clears the history too, so show what is really stored.
            .onChange(of: model.session) { Task { await history.reload() } }
            .onChange(of: profile.journalReminder) { _, on in Task { await reminders.setEveningJournal(enabled: on) } }
            .onChange(of: profile.actionsMorning) { Task { await reminders.setMorningActions(enabled: profile.actionsMorning, count: actions.pendingCount) } }
            .onChange(of: briefings.enabled) { Task { await refreshBriefings() } }
            .onChange(of: voices.voices) { Task { await refreshActions() } }
            .task(id: model.storedCount) {
                try? await Task.sleep(for: .seconds(2))   // let a burst of new moments settle first
                await refreshBriefings()
            }
            .task(id: model.storedCount) {
                try? await Task.sleep(for: .milliseconds(700))
                await refreshActions()
            }
    }

    /// Everything that runs once when the app opens: warming the language models, wiring what the phone and watch tell each other, and the dev hooks.
    private func start() async {
        // The language models load lazily; touching them now keeps the first question fast.
        let warm = Task.detached(priority: .utility) {
            _ = Embedder.vector(for: "warm up the plumber lease")
            _ = TextNormalizer.lemmas("warming up")
            _ = TextNormalizer.nameTokens(in: "Warm Up")
        }
        // Questions asked on the watch: answered here, shown here too, and logged like any other.
        ask.brain = SystemLocalBrain()
        ask.preferOnDevice = { UserDefaults.standard.bool(forKey: OnDevicePreference.key) }
        ask.mySpeakerID = { voices.me?.id }
        ask.spotFor = { chunk in
            guard chunk.coordinate != nil else { return nil }
            return places.label(for: chunk).map { .named($0) } ?? .unnamed
        }
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
        // "Hey Echo, ...": answered like any question, and the answer goes to the watch.
        link.wakeQuestion = { question in
            Task {
                var reply = await ask.quickAnswer(question, via: .wakeWord)
                reply.speak = profile.speakVoiceAnswers
                link.sendWakeAnswer(question: question, answer: reply)
            }
        }
        // Siri and Shortcuts use these same live models while the app is running.
        IntentHub.shared.ask = { question in await ask.quickAnswer(question, via: .typed) }
        IntentHub.shared.forget = { await forgetRecent(minutes: $0) }
        IntentHub.shared.promises = {
            let done = Set((UserDefaults.standard.string(forKey: DayWiper.promiseDoneKey) ?? "").split(separator: "\n").map(String.init))
            return IntentAnswers.promises(chunks: model.chunks, userName: profile.name, myVoice: voices.me?.id, done: done, today: DayID.today(now: model.now()))
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
        // Dev hook: `-seed-transcripts FILE` stores a day of transcripts directly (screenshots and checks without the watch).
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-seed-transcripts"), i + 1 < ProcessInfo.processInfo.arguments.count {
            let n = await DevSeed.load(path: ProcessInfo.processInfo.arguments[i + 1], into: model.store)
            Log.app.notice("seed-transcripts: \(n) moments")
            await model.load()
        }
        // Dev hooks: `-voice-me` says the voice heard most is the person's own, and `-name-places` names the demo day's places
        // (screenshots, the take).
        if ProcessInfo.processInfo.arguments.contains("-voice-me") { await introduceVoice() }
        if ProcessInfo.processInfo.arguments.contains("-name-places") { await introducePlaces() }
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
        await journal.load()
        // Dev hook: `-seed-calendar` adds an event with Priya, tomorrow at 13:00 (to see briefings work).
        if ProcessInfo.processInfo.arguments.contains("-seed-calendar") { await SystemCalendarReader.seed(title: "Lunch with Priya") }
        await reminders.setEveningJournal(enabled: profile.journalReminder)
        let args = ProcessInfo.processInfo.arguments
        // Dev hooks for headless verification: `-ask "question"` and `-digest` run once the day has loaded,
        // and `-demo-script` performs the whole demo in one take (see DemoDriver).
        if DemoDriver.requested {
            await warm.value
            await model.load()
            await DemoDriver(model: model, ask: ask, ledger: ledger, digest: digest, voice: voice, history: history,
                             today: today, player: player,
                             startWatch: { link.sendDemoStart(dayOffset: $0) },
                             forget: { await forgetRecent(minutes: $0) },
                             afterSync: { await introduceVoice(); await introducePlaces() },
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

/// Puts the app's shared models in the environment, in one place so the root view's body stays small enough to compile quickly.
private struct ModelEnvironment: ViewModifier {
    let speaker: Speaker
    let voices: VoiceBookModel
    let privacy: RecordingPrivacy
    let reminders: Reminders
    let calendar: CalendarLink
    let drafts: DraftModel
    let ledger: LedgerModel
    let briefings: BriefingCenter
    let places: PlacesModel
    let actions: ActionsModel
    let museActions: MuseActionsModel
    let performer: ActionPerformer

    func body(content: Content) -> some View {
        content
            .environment(speaker)
            .environment(voices)
            .environment(privacy)
            .environment(reminders)
            .environment(calendar)
            .environment(drafts)
            .environment(ledger)
            .environment(briefings)
            .environment(places)
            .environment(actions)
            .environment(museActions)
            .environment(performer)
    }
}
