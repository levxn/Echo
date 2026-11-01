import SwiftUI

/// Chunks moving through the pipeline as they arrive from the watch.
struct PipelineView: View {
    let model: PipelineModel

    @State private var showAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The feed shows the newest chunks until "Show all" is tapped.
    static let feedLimit = 12

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
        let newestFirst = Array(model.chunks.reversed())
        return VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Live feed") {
                if model.isSettled && model.storedCount > 0 {
                    Text("\(model.storedCount) stored · \(model.droppedCount) dropped")
                        .font(.footnote).monospacedDigit().foregroundStyle(Palette.textSecondary)
                }
            }
            if newestFirst.isEmpty {
                EmptyState(icon: "applewatch.radiowaves.left.and.right", title: "Nothing captured yet",
                           message: "Start the day on your watch and conversations appear here as they are checked, transcribed and stored on this phone.")
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(Capped.visible(newestFirst, limit: Self.feedLimit, showAll: showAll)) { chunk in
                        ChunkRow(chunk: chunk)
                            .transition(reduceMotion ? .opacity
                                        : .asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.15), value: model.chunks.count)
                ShowMoreButton(total: newestFirst.count, limit: Self.feedLimit, isExpanded: $showAll)
            }
        }
    }
}
