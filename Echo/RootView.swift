import SwiftUI

enum RootTab: String {
    case today, pipeline, ask, ledger
}

struct RootView: View {
    let model: PipelineModel

    @State private var ask: AskModel
    @State private var ledger: LedgerModel
    @State private var digest: DigestModel
    @State private var player: ChunkPlayer
    @State private var tab: RootTab

    init(model: PipelineModel) {
        self.model = model
        let ledger = LedgerModel(store: model.store)
        _ledger = State(initialValue: ledger)
        let client = MuseClientFactory.make()
        _ask = State(initialValue: AskModel(store: model.store, ledger: ledger, client: client))
        _digest = State(initialValue: DigestModel(store: model.store, ledger: ledger, client: client))
        _player = State(initialValue: ChunkPlayer(directory: model.store.chunksDirectory))
        // Dev hook: `simctl launch ... -tab ask` opens a tab directly.
        let args = ProcessInfo.processInfo.arguments
        let requested = args.firstIndex(of: "-tab").flatMap { $0 + 1 < args.count ? RootTab(rawValue: args[$0 + 1]) : nil }
        _tab = State(initialValue: requested ?? .today)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.horizon.fill", value: RootTab.today) { TodayView(model: model, digest: digest) }
            Tab("Pipeline", systemImage: "waveform.path", value: RootTab.pipeline) { PipelineView(model: model) }
            Tab("Ask", systemImage: "sparkles", value: RootTab.ask) {
                AskView(ask: ask, player: player, hasMemory: model.storedCount > 0)
            }
            Tab("Ledger", systemImage: "lock.shield.fill", value: RootTab.ledger) { LedgerView(ledger: ledger, model: model) }
        }
        .preferredColorScheme(.dark)
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
            await ledger.reload()
            await digest.load()
            let args = ProcessInfo.processInfo.arguments
            // Dev hooks for headless verification: `-ask "question"` and `-digest` run once the day has loaded.
            if let i = args.firstIndex(of: "-ask"), i + 1 < args.count {
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
