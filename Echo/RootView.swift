import SwiftUI

enum RootTab: String {
    case today, pipeline, ask
}

struct RootView: View {
    let model: PipelineModel

    @State private var ask: AskModel
    @State private var ledger: LedgerModel
    @State private var player: ChunkPlayer
    @State private var tab: RootTab

    init(model: PipelineModel) {
        self.model = model
        let ledger = LedgerModel(store: model.store)
        _ledger = State(initialValue: ledger)
        _ask = State(initialValue: AskModel(store: model.store, ledger: ledger, client: MuseClientFactory.make()))
        _player = State(initialValue: ChunkPlayer(directory: model.store.chunksDirectory))
        // Dev hook: `simctl launch ... -tab ask` opens a tab directly.
        let args = ProcessInfo.processInfo.arguments
        let requested = args.firstIndex(of: "-tab").flatMap { $0 + 1 < args.count ? RootTab(rawValue: args[$0 + 1]) : nil }
        _tab = State(initialValue: requested ?? .today)
    }

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.horizon.fill", value: RootTab.today) { TodayView(model: model) }
            Tab("Pipeline", systemImage: "waveform.path", value: RootTab.pipeline) { PipelineView(model: model) }
            Tab("Ask", systemImage: "sparkles", value: RootTab.ask) {
                AskView(ask: ask, player: player, hasMemory: model.storedCount > 0)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            // The language models load lazily; touching them now keeps the first question fast.
            let warm = Task.detached(priority: .utility) {
                _ = Embedder.vector(for: "warm up the plumber lease")
                _ = TextNormalizer.lemmas("warming up")
                _ = TextNormalizer.nameTokens(in: "Warm Up")
            }
            await ledger.reload()
            // Dev hook: `-ask "question"` runs a query once the stored day has loaded.
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-ask"), i + 1 < args.count else { return }
            await warm.value
            await model.load()
            tab = .ask
            await ask.ask(args[i + 1])
        }
    }
}
