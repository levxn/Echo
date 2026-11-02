import Observation
import SwiftUI

/// The four views of the day under the funnel on Today.
enum TodaySection: String, CaseIterable, Identifiable {
    case summary, commitments, people, day
    var id: String { rawValue }

    /// The segment label, with a count where one helps ("Promises 15").
    func title(commitments: Int, people: Int, conversations: Int) -> String {
        switch self {
        case .summary: "Summary"
        case .commitments: commitments > 0 ? "Promises \(commitments)" : "Promises"
        case .people: people > 0 ? "People \(people)" : "People"
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
    /// Scrolls Today to an anchor ("sections", "todayTop"). Set by the demo driver only.
    var scrollTarget: String?
}

/// The funnel, then the day as a summary, its commitments, or its conversations: one at a time, so each fits a screen.
struct TodayView: View {
    let model: PipelineModel
    let digest: DigestModel
    let player: ChunkPlayer
    let state: TodayState
    let profile: ProfileStore
    /// Asks the Ask tab a question (from a person's page).
    var onAsk: (String) -> Void = { _ in }

    @State private var episodes: [Episode] = []
    @State private var promises: [Promise] = []
    @State private var heardPeople: [Person] = []
    @AppStorage(PeopleIgnore.key) private var ignoredPeople = ""
    @State private var focusedSections = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var people: [Person] { PeopleIgnore.visible(heardPeople, ignoring: ignoredPeople) }

    private var statusText: String {
        switch model.session {
        case .waiting: model.watchReachable ? "Watch connected" : "Waiting for your watch"
        case .running: "Listening · \(Int(model.sessionFraction * 100))% of the day"
        case .finished: model.isSettled ? "Day synced and processed" : "Processing \(model.pendingCount + model.missingCount) left"
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: Spacing.xl) {
                greeting.id("todayTop")
                FunnelCard(model: model)
                if model.todayChunks.isEmpty {
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
            episodes = EpisodeBuilder.build(from: model.todayChunks)
            promises = PromiseExtractor.extract(from: model.todayChunks, userName: profile.name)
            if model.storedCount == 0 { digest.reset() }
            refreshPeople()
        }
        // Dev hook: with `-today-focus` or `-today-section`, scroll so the switcher and its content fill the screen
        // once the day has loaded (screenshots, demo take).
        .onChange(of: profile.name) {
            promises = PromiseExtractor.extract(from: model.todayChunks, userName: profile.name)
            refreshPeople()
        }
        .onChange(of: state.scrollTarget) { _, target in
            guard let target else { return }
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) { proxy.scrollTo(target, anchor: .top) }
        }
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

    /// "Good evening, Levin" and one line on where the day stands.
    private var greeting: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(profile.greeting)
                .font(.echoScreenTitle)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Spacing.tight) {
                Circle().fill(model.watchReachable ? Palette.teal : Palette.amber).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .contentTransition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sections: some View {
        VStack(spacing: Spacing.xl) {
            EchoSegmented(
                segments: TodaySection.allCases.map {
                    .init(value: $0, title: $0.title(commitments: promises.count, people: people.count, conversations: episodes.count))
                },
                selection: Bindable(state).section)
            Group {
                switch state.section {
                case .summary: summary
                case .commitments: commitments
                case .people: peopleView
                case .day: day
                }
            }
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: state.section)
    }

    @ViewBuilder
    private var summary: some View {
        VStack(spacing: Spacing.xl) {
            ForEach(Resurfacing.suggestions(from: model.chunks, now: model.now())) { item in
                ResurfacedCard(item: item) { onAsk(item.question) }
            }
            summaryToday
            if model.storedCount > model.todayChunks.filter({ $0.status == .stored }).count {
                EchoButton(title: "Summarize my week with Muse", systemImage: "calendar", action: { onAsk("Summarize my past week") })
            }
        }
    }

    @ViewBuilder
    private var summaryToday: some View {
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

    /// Name-finding runs the on-device tagger over the whole day, so it happens off the main thread.
    private func refreshPeople() {
        let chunks = model.chunks, name = profile.name
        Task {
            let found = await Task.detached(priority: .utility) { PeopleIndex.build(from: chunks, userName: name) }.value
            heardPeople = found
        }
    }

    @ViewBuilder
    private var peopleView: some View {
        if people.isEmpty {
            EmptyState(icon: "person.2", tint: Palette.blue, title: "No names heard yet",
                       message: "People who are mentioned or spoken to appear here as conversations are transcribed.")
        } else {
            PeopleSection(people: people, promises: promises, model: model, player: player, onAsk: onAsk,
                          onIgnore: { ignoredPeople = PeopleIgnore.raw(adding: $0.id, to: ignoredPeople) })
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

/// Shown before anything has been captured.
private struct EmptyDayHint: View {
    var body: some View {
        EmptyState(icon: "applewatch.radiowaves.left.and.right", title: "Your day starts on the watch",
                   message: "Tap Start day on the watch. Conversations are checked, transcribed and stored on this phone, then summarized here as a timeline.")
    }
}
