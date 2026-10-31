import SwiftUI

/// The settled summary of the day. The day timeline is added here.
struct TodayView: View {
    let model: PipelineModel
    let digest: DigestModel
    let player: ChunkPlayer

    @State private var episodes: [Episode] = []
    @State private var promises: [Promise] = []
    @State private var focusedPromises = false

    private var statusText: String {
        switch model.session {
        case .waiting: model.watchReachable ? "Watch connected" : "Waiting for your watch"
        case .running: "Listening · \(Int(model.sessionFraction * 100))% of the day"
        case .finished: model.isSettled ? "Day synced and processed" : "Processing \(model.pendingCount) left"
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: Spacing.xl) {
                ScreenHeader(title: "Echo", status: statusText, reachable: model.watchReachable) {
                    Task { await model.reset() }
                }
                FunnelCard(model: model)
                if model.chunks.isEmpty { EmptyDayHint() }
                if model.isSettled { DigestSection(digest: digest, model: model, player: player) }
                if !promises.isEmpty {
                    PromisesSection(promises: promises, model: model, player: player)
                        .id("promises")
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
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
            withAnimation(.smooth(duration: 0.5)) {
                episodes = EpisodeBuilder.build(from: model.chunks)
                promises = PromiseExtractor.extract(from: model.chunks)
            }
            if model.storedCount == 0 { digest.reset() }
        }
        // Dev hook: `-today-focus promises` scrolls to the commitments once they exist (screenshots, demo take).
        .onChange(of: promises.count) {
            let args = ProcessInfo.processInfo.arguments
            guard !focusedPromises, !promises.isEmpty,
                  let i = args.firstIndex(of: "-today-focus"), i + 1 < args.count, args[i + 1] == "promises" else { return }
            focusedPromises = true
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo("promises", anchor: .top) }
            }
        }
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
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
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

/// Shown before anything has been captured.
private struct EmptyDayHint: View {
    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 28))
                .foregroundStyle(Palette.blue)
            Text("Your day starts on the watch")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
            Text("Tap Start day on the watch. Conversations are checked, transcribed and stored on this phone, then summarized here as a timeline.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .echoCard(padding: Spacing.xl)
    }
}
