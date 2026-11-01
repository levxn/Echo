import SwiftUI

/// Chunks moving through the pipeline as they arrive from the watch.
struct PipelineView: View {
    let model: PipelineModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                ScreenHeader(title: "Pipeline",
                             status: model.pendingCount > 0 ? "Processing \(model.pendingCount) moments" : "Idle",
                             reachable: model.watchReachable)
                StageStrip(model: model)
                feed
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Live feed")
            if model.chunks.isEmpty {
                EmptyState(icon: "applewatch.radiowaves.left.and.right", title: "Nothing captured yet",
                           message: "Start the day on your watch and conversations appear here as they are checked, transcribed and stored on this phone.")
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(model.chunks.reversed()) { chunk in
                        ChunkRow(chunk: chunk)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }
                .animation(.spring(duration: 0.4, bounce: 0.15), value: model.chunks.count)
            }
        }
    }
}
