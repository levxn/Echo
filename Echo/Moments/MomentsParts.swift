import Charts
import SwiftUI
import Translation

// MARK: - The day's graph

/// "When it listened": the whole day as a bar chart, a bar for every quarter of an hour the microphone was on, taller the more was heard.
/// Tapping it jumps to the nearest conversation.
struct DayActivityChart: View {
    let chunks: [ChunkRecord]
    let groups: [MomentGroup]
    /// A slimmer version with no title and no grid, for the top of the Day page.
    var compact = false
    let onSelect: (Int) -> Void

    private struct Bar: Identifiable {
        let id: Int
        let time: Date
        let value: Double
    }

    private static let quarterHour = 900.0
    private var graph: DayActivity.Graph? { DayActivity.graph(spans: chunks.map { (start: $0.wallStart, duration: $0.duration) }, bin: Self.quarterHour) }
    /// Any midnight will do: only the time of day is drawn.
    private let midnight = Calendar.current.startOfDay(for: Date())

    private func date(_ seconds: Double) -> Date { midnight.addingTimeInterval(seconds) }

    var body: some View {
        if let graph {
            let bars = graph.values.enumerated().filter { $0.element > 0 }.map {
                Bar(id: $0.offset, time: date(graph.start + Double($0.offset) * graph.bin), value: max($0.element, 0.12))
            }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                if !compact { SectionHeader("When it listened", style: .overline) }
                Chart(bars) { bar in
                    BarMark(x: .value("Time", bar.time), y: .value("Heard", bar.value), width: .fixed(compact ? 5 : 7))
                        .foregroundStyle(LinearGradient(colors: [Palette.teal, Palette.blue], startPoint: .top, endPoint: .bottom))
                        .cornerRadius(compact ? 2.5 : 3.5)
                }
                .chartXScale(domain: date(graph.start)...date(graph.end), range: .plotDimension(startPadding: 16, endPadding: 16))
                .chartYScale(domain: 0...1.05)
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: DayActivity.hourLabels(graph).map { date(graph.start + $0.offset * (graph.end - graph.start)) }) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(compact ? Color.clear : Palette.stroke)
                        AxisValueLabel(format: .dateTime.hour(), anchor: .top).foregroundStyle(Palette.textSecondary)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .onTapGesture { location in
                                guard let plot = proxy.plotFrame, let tapped: Date = proxy.value(atX: location.x - geo[plot].origin.x) else { return }
                                select(seconds: tapped.timeIntervalSince(midnight))
                            }
                    }
                }
                .frame(height: compact ? 84 : 148)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("The day: a bar for every quarter of an hour the microphone was on, between \(DayActivity.hourLabels(graph).first?.text ?? "") and \(DayActivity.hourLabels(graph).last?.text ?? "")")
                .accessibilityHint("Tap to jump to a conversation")
            }
        }
    }

    private func select(seconds: Double) {
        guard !groups.isEmpty else { return }
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
