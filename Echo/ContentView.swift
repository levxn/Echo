import SwiftUI

struct ContentView: View {
    let model: PipelineModel

    private var statusText: String {
        switch model.session {
        case .waiting: model.watchReachable ? "Watch connected" : "Waiting for your watch"
        case .running: "Listening · \(Int(model.sessionFraction * 100))% of the day"
        case .finished: model.isSettled ? "Day synced and processed" : "Processing \(model.pendingCount) left"
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    header
                    FunnelCard(model: model)
                    StageStrip(model: model)
                    feed
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Echo")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.watchReachable ? Palette.teal : Palette.amber)
                        .frame(width: 8, height: 8)
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.opacity)
                }
                .animation(.easeOut(duration: 0.2), value: statusText)
            }
            Spacer()
            Button {
                Task { await model.reset() }
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(EchoPressStyle())
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Clear today's memory")
        }
    }

    private var feed: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Live pipeline")
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
