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

    @State private var ask: AskModel
    @State private var ledger: LedgerModel
    @State private var digest: DigestModel
    @State private var player: ChunkPlayer
    @State private var today = TodayState()
    @State private var profile = ProfileStore()
    @State private var showProfile = ProcessInfo.processInfo.arguments.contains("-show-profile")
    @State private var tab: RootTab
    @State private var caption: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: PipelineModel, link: PhoneLink) {
        self.model = model
        self.link = link
        let ledger = LedgerModel(store: model.store)
        _ledger = State(initialValue: ledger)
        let client = MuseClientFactory.make()
        _ask = State(initialValue: AskModel(store: model.store, ledger: ledger, client: client))
        _digest = State(initialValue: DigestModel(store: model.store, ledger: ledger, client: client))
        _player = State(initialValue: ChunkPlayer(directory: model.store.chunksDirectory))
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

    private func forgetDay(includeLedger: Bool) {
        Task {
            await DayWiper.forget(resetDay: { await model.reset() }, ask: ask, digest: digest, player: player,
                                  ledger: ledger, includeLedger: includeLedger)
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.horizon.fill", value: RootTab.today) {
                TodayView(model: model, digest: digest, player: player, state: today, profile: profile)
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.today) }
            }
            Tab("Moments", systemImage: "waveform", value: RootTab.moments) {
                MomentsView(model: model, player: player) { ledger.showArchitecture = true }
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.moments) }
            }
            Tab("Ask", systemImage: "sparkles", value: RootTab.ask) {
                AskView(ask: ask, player: player, hasMemory: model.storedCount > 0, chunks: model.chunks)
                    .safeAreaBar(edge: .top, spacing: 0) { topBar(.ask) }
            }
            Tab("Ledger", systemImage: "lock.shield.fill", value: RootTab.ledger) {
                LedgerView(ledger: ledger, model: model) { includeLedger in forgetDay(includeLedger: includeLedger) }
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
            link.onAsk = { question in
                await warm.value
                tab = .ask
                let answer = await ask.quickAnswer(question)
                Log.link.notice("watch ask: \(answer.source.rawValue) in \(answer.milliseconds) ms")
                return answer
            }
            await ledger.reload()
            await digest.load()
            let args = ProcessInfo.processInfo.arguments
            // Dev hooks for headless verification: `-ask "question"` and `-digest` run once the day has loaded,
            // and `-demo-script` performs the whole demo in one take (see DemoDriver).
            if DemoDriver.requested {
                await warm.value
                await model.load()
                await DemoDriver(model: model, ask: ask, ledger: ledger, digest: digest, today: today, player: player,
                                 startWatch: { link.sendDemoStart() },
                                 watchQuickAsk: { link.sendDemoQuickAsk($0) },
                                 setTab: { tab = $0 },
                                 setCaption: { caption = $0 }).run()
            } else if let i = args.firstIndex(of: "-ask"), i + 1 < args.count {
                await warm.value
                await model.load()
                tab = .ask
                await ask.ask(args[i + 1])
            } else if args.contains("-digest") {
                await model.load()
                tab = .today
                await digest.generate(chunks: model.chunks)
            }
        }
    }
}
