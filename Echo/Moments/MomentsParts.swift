import SwiftUI
import Translation

// MARK: - The day's graph

/// "When it listened": the whole day as one graph, with a spike wherever the microphone was on. Tapping it jumps to the nearest conversation.
struct DayActivityChart: View {
    let chunks: [ChunkRecord]
    let groups: [MomentGroup]
    let onSelect: (Int) -> Void

    private var graph: DayActivity.Graph? { DayActivity.graph(spans: chunks.map { (start: $0.wallStart, duration: $0.duration) }) }

    var body: some View {
        if let graph {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader("When it listened", style: .overline)
                VStack(spacing: Spacing.xs) {
                    GeometryReader { geo in
                        Canvas { context, size in draw(graph, in: &context, size: size) }
                            .contentShape(Rectangle())
                            .onTapGesture { point in select(at: point.x / max(geo.size.width, 1), graph: graph) }
                    }
                    .frame(height: 112)
                    axis(graph)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, Spacing.sm)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The day: spikes show when the microphone was on, between \(DayActivity.hourLabels(graph).first?.text ?? "") and \(DayActivity.hourLabels(graph).last?.text ?? "")")
                .accessibilityHint("Tap to jump to a conversation")
            }
        }
    }

    private func draw(_ graph: DayActivity.Graph, in context: inout GraphicsContext, size: CGSize) {
        let count = graph.values.count
        guard count > 0 else { return }
        let slot = size.width / CGFloat(count)
        let floorY = size.height - 2
        let span = size.height - 8
        // Each peak is spread a little over its neighbours, so a burst of speech is a hill you can see and tap, not a hairline.
        var shown = graph.values.indices.map { i -> Double in
            let before = i > 0 ? graph.values[i - 1] : 0, after = i < count - 1 ? graph.values[i + 1] : 0
            return before * 0.35 + graph.values[i] + after * 0.35
        }
        let tallest = shown.max() ?? 1
        if tallest > 0 { shown = shown.map { $0 / tallest } }
        func point(_ index: Int) -> CGPoint {
            // A gentle curve on the height keeps a short burst of speech visible next to a long one.
            CGPoint(x: (CGFloat(index) + 0.5) * slot, y: floorY - CGFloat(pow(shown[index], 0.7)) * span)
        }
        // One continuous shape for the whole day: flat where nothing was heard, a peak where the microphone was on.
        var line = Path()
        line.move(to: CGPoint(x: 0, y: floorY))
        for index in 0..<count { line.addLine(to: point(index)) }
        line.addLine(to: CGPoint(x: size.width, y: floorY))
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        context.fill(area, with: .linearGradient(Gradient(colors: [Palette.teal.opacity(0.6), Palette.blue.opacity(0.05)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
        context.stroke(line, with: .linearGradient(Gradient(colors: [Palette.teal, Palette.blue]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    private func axis(_ graph: DayActivity.Graph) -> some View {
        GeometryReader { geo in
            ForEach(DayActivity.hourLabels(graph), id: \.text) { label in
                Text(label.text)
                    .font(Font.echoMicro.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize()
                    .position(x: min(max(label.offset * geo.size.width, 14), geo.size.width - 14), y: 8)
            }
        }
        .frame(height: 16)
    }

    private func select(at fraction: CGFloat, graph: DayActivity.Graph) {
        guard !groups.isEmpty else { return }
        let seconds = graph.start + Double(min(max(fraction, 0), 1)) * (graph.end - graph.start)
        if let nearest = groups.min(by: { abs(Double($0.id) - seconds) < abs(Double($1.id) - seconds) }) { onSelect(nearest.id) }
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
                    }
                }
            }
        }
        // No animation here on purpose: while the day arrives, groups open and close by themselves, and animating
        // that made old and new text overlap. A tap animates (see MomentsView).
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
    @Environment(VoiceBookModel.self) private var voices
    @State private var translating = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
            // A small circle with the speaker's first letter, but only once the voice has a name: "2" or "4" meant nothing to anyone.
            if let voice = voices.voice(id: item.speakerId), voice.name?.isEmpty == false { VoiceDot(voice: voice) }
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
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { expanded.toggle() } }
                    .accessibilityAction(named: expanded ? "Show less" : "Show all of it") { expanded.toggle() }
                PlayButton(isPlaying: isPlaying, label: "Play the audio from \(item.timeLabel)", action: onPlay)
                Menu {
                    Button("Translate…", systemImage: "translate") { translating = true }
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
        .translationPresentation(isPresented: $translating, text: item.text ?? "")
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
