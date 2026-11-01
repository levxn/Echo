import SwiftUI

// MARK: - Status banner

/// "Listening", "Catching up", "Caught up": one card that answers whether the watch is working and the phone is keeping up.
struct MomentsStatusCard: View {
    let status: CaptureStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tint: Color {
        switch status.kind {
        case .waitingForWatch: Palette.amber
        case .watchReady, .caughtUp: Palette.teal
        case .listening, .catchingUp: Palette.blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                Image(systemName: status.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .symbolEffect(.variableColor.iterative, isActive: status.kind == .listening && !reduceMotion)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(status.title)
                        .font(.echoSection)
                        .foregroundStyle(Palette.textPrimary)
                    Text(status.detail)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            if let progress = status.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.fillStrong)
                        Capsule().fill(tint).frame(width: max(8, geo.size.width * min(1, max(0, progress))))
                    }
                }
                .frame(height: 6)
                .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: progress)
            }
            if let footnote = status.footnote {
                Label(footnote, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: status.kind)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.title)
        .accessibilityValue([status.detail, status.progress.map { "\(Int(($0 * 100).rounded())) percent" }]
            .compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - The ribbon

/// "When it listened": one block per conversation, one bar per moment, start time underneath. Tapping a block jumps to it.
struct ListeningRibbon: View {
    let groups: [MomentGroup]
    let onSelect: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spacing = Spacing.sm

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("When it listened", style: .overline)
            GeometryReader { geo in
                let shares = Ribbon.shares(counts: groups.map(\.count))
                let usable = max(0, geo.size.width - spacing * CGFloat(max(0, groups.count - 1)))
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        Button { onSelect(group.id) } label: {
                            block(group)
                        }
                        .buttonStyle(EchoPressStyle())
                        .frame(width: usable * shares[index])
                        .accessibilityLabel("Conversation at \(group.startLabel), \(group.count) moment\(group.count == 1 ? "" : "s")")
                        .accessibilityHint("Jumps to it")
                    }
                }
            }
            .frame(height: 76)
            .animation(reduceMotion ? nil : .smooth(duration: 0.4), value: groups.map(\.count))
        }
    }

    private func block(_ group: MomentGroup) -> some View {
        let heights = Ribbon.bars(durations: group.items.map(\.duration))
        return VStack(spacing: Spacing.tight) {
            HStack(alignment: .bottom, spacing: Spacing.xxs) {
                ForEach(Array(heights.enumerated()), id: \.offset) { _, h in
                    Capsule()
                        .fill(Palette.accentGradient)
                        .frame(maxWidth: 7)   // a conversation with few moments stays a small cluster, not fat blobs
                        .frame(height: 8 + 28 * h)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 36, alignment: .bottom)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            Text(group.startLabel)
                .font(Font.echoMeta.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textSecondary)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - A conversation and its moments

struct MomentGroupView: View {
    let group: MomentGroup
    let isOpen: Bool
    let playingID: String?
    let onToggle: () -> Void
    let onPlay: (MomentItem) -> Void
    let onDelete: (MomentItem) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// With very large text the title goes on its own line instead of being cut off.
    private var headerLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs)) : AnyLayout(HStackLayout(spacing: Spacing.md))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onToggle) {
                headerLayout {
                    HStack(spacing: Spacing.md) {
                        Text(group.startLabel)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textPrimary)
                        if !typeSize.isAccessibilitySize { title }
                        Spacer(minLength: Spacing.sm)
                        Text("\(group.count)")
                            .font(Font.echoMeta.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    if typeSize.isAccessibilitySize { title }
                }
                .frame(minHeight: 44)
                .echoRow(vertical: typeSize.isAccessibilitySize ? Spacing.sm : 0, fill: Palette.fillStrong)
                .contentShape(Rectangle())
            }
            .buttonStyle(EchoPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(group.startLabel), \(group.title), \(group.count) moments")
            .accessibilityValue(isOpen ? "expanded" : "collapsed")
            .accessibilityHint(isOpen ? "Collapses the moments" : "Shows the moments")
            .accessibilityAddTraits([.isHeader, .isButton])

            if isOpen {
                VStack(spacing: Spacing.sm) {
                    ForEach(group.items) { item in
                        MomentRowView(item: item, isPlaying: playingID == item.id,
                                      onPlay: { onPlay(item) }, onDelete: { onDelete(item) })
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: isOpen)
    }

    private var title: some View {
        Text(group.title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Palette.textSecondary)
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
    }
}

struct MomentRowView: View {
    let item: MomentItem
    let isPlaying: Bool
    let onPlay: () -> Void
    let onDelete: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var time: some View {
        Text(item.timeLabel)
            .font(Font.echoMeta.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Palette.textSecondary)
            .fixedSize()
    }

    var body: some View {
        // With very large text the time sits above the transcript, so neither is squeezed.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                                                  : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.md))
        layout {
            time
                .frame(width: typeSize.isAccessibilitySize ? nil : 44, alignment: .leading)
            if let text = item.text, item.inFlight {
                // Transcribed, but not saved yet: shown, but not playable or deletable until it is.
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ProgressView().controlSize(.small).tint(Palette.blue).frame(width: 44, height: 44)
            } else if let text = item.text {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                PlayButton(isPlaying: isPlaying, label: "Play the audio from \(item.timeLabel)", action: onPlay)
                Menu {
                    Button("Delete this moment", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("More for the moment at \(item.timeLabel)")
            } else {
                HStack(spacing: Spacing.sm) {
                    ProgressView().controlSize(.small).tint(Palette.blue)
                    Text("Understanding…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
            }
        }
        .echoRow(vertical: Spacing.xs)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Behind the scenes

/// The technical story in plain sentences, closed by default.
struct BehindTheScenesView: View {
    let lines: [String]
    @Binding var isOpen: Bool
    let onHowItWorks: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                ForEach(lines, id: \.self) { line in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Circle().fill(Palette.textTertiary).frame(width: 5, height: 5).padding(.top, 7).accessibilityHidden(true)
                        Text(line)
                            .font(.footnote)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                EchoButton(title: "How Echo works", systemImage: "square.stack.3d.up.fill", action: onHowItWorks)
            }
            .padding(.top, Spacing.xs)
        } label: {
            Label("Behind the scenes", systemImage: "gearshape.2")
                .font(.echoLabel)
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 44)
        }
        .tint(Palette.textSecondary)
        .echoCard()
    }
}
