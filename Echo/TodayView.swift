import SwiftUI

/// The settled summary of the day. The day timeline is added here.
struct TodayView: View {
    let model: PipelineModel
    let digest: DigestModel

    @State private var episodes: [Episode] = []

    private var statusText: String {
        switch model.session {
        case .waiting: model.watchReachable ? "Watch connected" : "Waiting for your watch"
        case .running: "Listening · \(Int(model.sessionFraction * 100))% of the day"
        case .finished: model.isSettled ? "Day synced and processed" : "Processing \(model.pendingCount) left"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                ScreenHeader(title: "Echo", status: statusText, reachable: model.watchReachable) {
                    Task { await model.reset() }
                }
                FunnelCard(model: model)
                if model.isSettled { DigestSection(digest: digest, model: model) }
                if !episodes.isEmpty {
                    EpisodesSection(episodes: episodes)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .onChange(of: model.storedCount, initial: true) {
            withAnimation(.smooth(duration: 0.5)) { episodes = EpisodeBuilder.build(from: model.chunks) }
            if model.storedCount == 0 { digest.reset() }
        }
    }
}

struct ScreenHeader: View {
    let title: String
    let status: String
    let reachable: Bool
    var onReset: (() -> Void)?

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(reachable ? Palette.teal : Palette.amber)
                        .frame(width: 8, height: 8)
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.opacity)
                }
                .animation(.easeOut(duration: 0.2), value: status)
            }
            Spacer()
            if let onReset {
                Button(action: onReset) {
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
    }
}
