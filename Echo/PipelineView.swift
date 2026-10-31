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
            Text("Live feed")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            if model.chunks.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "applewatch.radiowaves.left.and.right")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.blue)
                    Text("Nothing captured yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Start the day on your watch and conversations appear here as they are checked, transcribed and stored on this phone.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .echoCard(padding: Spacing.xl)
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
