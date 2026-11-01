import Observation
import SwiftUI

/// The three views of the day under the funnel on Today.
enum TodaySection: String, CaseIterable, Identifiable {
    case summary, commitments, day
    var id: String { rawValue }

    /// The segment label, with a count where one helps ("Commitments 15").
    func title(commitments: Int, conversations: Int) -> String {
        switch self {
        case .summary: "Summary"
        case .commitments: commitments > 0 ? "Commitments \(commitments)" : "Commitments"
        case .day: conversations > 0 ? "Day \(conversations)" : "Day"
        }
    }

    /// Dev hooks for screenshots and the demo take: `-today-section summary|commitments|day`, and the older
    /// `-today-focus promises`, which opens Commitments.
    static func initial(arguments: [String]) -> TodaySection {
        if let i = arguments.firstIndex(of: "-today-section"), i + 1 < arguments.count,
           let section = TodaySection(rawValue: arguments[i + 1]) { return section }
        if let i = arguments.firstIndex(of: "-today-focus"), i + 1 < arguments.count, arguments[i + 1] == "promises" { return .commitments }
        return .summary
    }
}

/// Which section of Today is showing. Lives outside the view so the demo driver can switch it.
@MainActor
@Observable
final class TodayState {
    var section = TodaySection.initial(arguments: ProcessInfo.processInfo.arguments)
}

/// The funnel, then the day as a summary, its commitments, or its conversations: one at a time, so each fits a screen.
struct TodayView: View {
    let model: PipelineModel
    let digest: DigestModel
    let player: ChunkPlayer
    let state: TodayState

    @State private var episodes: [Episode] = []
    @State private var promises: [Promise] = []
    @State private var focusedSections = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                if model.chunks.isEmpty {
                    EmptyDayHint()
                } else {
                    sections.id("sections")
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .onChange(of: model.storedCount, initial: true) {
            episodes = EpisodeBuilder.build(from: model.chunks)
            promises = PromiseExtractor.extract(from: model.chunks)
            if model.storedCount == 0 { digest.reset() }
        }
        // Dev hook: with `-today-focus` or `-today-section`, scroll so the switcher and its content fill the screen
        // once the day has loaded (screenshots, demo take).
        .onChange(of: promises.count) {
            let args = ProcessInfo.processInfo.arguments
            guard !focusedSections, !promises.isEmpty, args.contains("-today-focus") || args.contains("-today-section") else { return }
            focusedSections = true
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { proxy.scrollTo("sections", anchor: .top) }
            }
        }
        }
    }

    private var sections: some View {
        VStack(spacing: Spacing.xl) {
            EchoSegmented(
                segments: TodaySection.allCases.map {
                    .init(value: $0, title: $0.title(commitments: promises.count, conversations: episodes.count))
                },
                selection: Bindable(state).section)
            Group {
                switch state.section {
                case .summary: summary
                case .commitments: commitments
                case .day: day
                }
            }
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state.section)
    }

    @ViewBuilder
    private var summary: some View {
        if model.isSettled {
            DigestSection(digest: digest, model: model, player: player)
        } else {
            EmptyState(icon: "hourglass", tint: Palette.blue, title: "Still processing",
                       message: "Muse can summarize the day once everything has been checked and transcribed on this phone.")
        }
    }

    @ViewBuilder
    private var commitments: some View {
        if promises.isEmpty {
            EmptyState(icon: "checkmark.circle", tint: Palette.teal, title: "No commitments heard yet",
                       message: "Things people say they will do, like \u{201C}I will send it Friday\u{201D}, are collected here as they are transcribed.")
        } else {
            PromisesSection(promises: promises, model: model, player: player)
        }
    }

    @ViewBuilder
    private var day: some View {
        if episodes.isEmpty {
            EmptyState(icon: "text.bubble", tint: Palette.blue, title: "No conversations yet",
                       message: "Conversations appear here as a timeline once they have been transcribed.")
        } else {
            EpisodesSection(episodes: episodes)
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
        EmptyState(icon: "applewatch.radiowaves.left.and.right", title: "Your day starts on the watch",
                   message: "Tap Start day on the watch. Conversations are checked, transcribed and stored on this phone, then summarized here as a timeline.")
    }
}
