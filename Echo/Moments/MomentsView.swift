import SwiftUI

/// What the watch heard today, in plain language: is it listening, has the phone caught up, and the moments themselves
/// grouped by conversation, each one playable and deletable. The technical story lives under "Behind the scenes".
struct MomentsView: View {
    let model: PipelineModel
    let player: ChunkPlayer
    let privacy: RecordingPrivacy
    let onShowHowItWorks: () -> Void

    @State private var overrides: [Int: Bool] = [:]
    @State private var showBehind = ProcessInfo.processInfo.arguments.contains("-moments-behind")
    @State private var pendingDelete: MomentItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Dev hook: `-moments-expand all|latest|none` fixes which conversations are open (screenshots, the demo take).
    private static let expandMode: String? = {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: "-moments-expand").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }()

    var body: some View {
        let layout = MomentsLayout.make(from: model.sessionChunks)
        let defaults = MomentsLayout.openGroups(layout, settled: model.isSettled, mode: Self.expandMode)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    PrivacyBanner(privacy: privacy, listening: model.isListening)
                    if layout.groups.isEmpty && layout.working.isEmpty {
                        EmptyState(icon: "waveform", tint: Palette.blue, title: "Nothing heard yet",
                                   message: "Moments appear here as your watch hears them.")
                    } else {
                        if !layout.groups.isEmpty {
                            DayActivityChart(chunks: model.sessionChunks.filter { $0.status != .dropped }, groups: layout.groups) { id in
                                overrides[id] = true
                                withAnimation(reduceMotion ? nil : .smooth(duration: 0.5)) { proxy.scrollTo(id, anchor: .top) }
                            }
                        }
                        feed(layout, defaults: defaults)
                    }
                    BehindTheScenesView(lines: lines(layout), isOpen: $showBehind, onHowItWorks: onShowHowItWorks)
                        .id("behind")
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .background { AuroraBackground() }
            // Dev hook: `-play-first` starts the newest moment's audio, so the playing state can be seen (screenshots).
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-play-first") else { return }
                try? await Task.sleep(for: .milliseconds(1200))
                let stored = model.sessionChunks.filter { $0.status == .stored }
                // The first moment of the newest conversation, which is the one open at the top of the list.
                if let newest = stored.last, let first = stored.filter({ $0.wallStart >= newest.wallStart - 300 }).min(by: { $0.wallStart < $1.wallStart }) { player.toggle(first) }
            }
            // Dev hook: `-moments-behind` opens Behind the scenes and scrolls to it (screenshots).
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-moments-behind") else { return }
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.6)) { proxy.scrollTo("behind", anchor: .bottom) }
            }
        }
        .confirmationDialog("Delete this moment?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { item in
            Button("Delete the moment at \(item.timeLabel)", role: .destructive) { delete(item) }
        } message: { _ in
            Text("Its transcript, audio and search entry are removed from this phone. Summaries already written aren't changed.")
        }
    }

    // MARK: Feed

    @ViewBuilder
    private func feed(_ layout: MomentsLayout, defaults: Set<Int>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if !layout.working.isEmpty {
                SectionHeader("Just arrived", style: .overline)
                ForEach(layout.working.prefix(3)) { item in
                    MomentRowView(item: item, isPlaying: false, onPlay: {}, onDelete: {})
                }
                if layout.working.count > 3 {
                    Text("and \(layout.working.count - 3) more being understood")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            SectionHeader("Moments", meta: "\(layout.groups.map(\.count).reduce(0, +))")
            ForEach(layout.groups.reversed()) { group in
                MomentGroupView(group: group, isOpen: overrides[group.id] ?? defaults.contains(group.id), playingID: player.playingID,
                                onToggle: { withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { overrides[group.id] = !(overrides[group.id] ?? defaults.contains(group.id)) } },
                                onPlay: { item in if let chunk = model.record(id: item.id) { player.toggle(chunk) } },
                                onDelete: { pendingDelete = $0 })
                    .id(group.id)
            }
        }
    }

    private func lines(_ layout: MomentsLayout) -> [String] {
        BehindTheScenes.lines(arrived: model.arrivedCount, stored: model.storedCount, ignored: layout.ignored, failed: layout.failed,
                              recorded: model.recordedSeconds, kept: model.watchKeptSeconds, confirmed: model.phoneConfirmedSeconds)
    }

    private func delete(_ item: MomentItem) {
        if player.playingID == item.id { player.stop() }
        Task { await model.remove(id: item.id) }
    }
}
