import SwiftUI

/// A full-width glass capsule button. One height (48pt) everywhere.
struct EchoButton: View {
    enum Style {
        case prominent      // the one primary action on a screen (tinted glass)
        case secondary      // ordinary glass
        case destructive    // glass with rose text
        case quiet          // text only
    }

    let title: String
    var systemImage: String?
    var style: Style = .secondary
    var tint: Color = Palette.cloud
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Capsule())
        }
        .buttonStyle(EchoPressStyle())
        .modifier(GlassIfNeeded(style: style, tint: tint))
    }

    private var foreground: Color {
        switch style {
        case .prominent, .secondary: Palette.textPrimary
        case .destructive: Palette.rose
        case .quiet: Palette.textSecondary
        }
    }

    private struct GlassIfNeeded: ViewModifier {
        let style: Style
        let tint: Color

        func body(content: Content) -> some View {
            switch style {
            case .prominent: content.glassEffect(.regular.tint(tint.opacity(0.4)).interactive(), in: .capsule)
            case .secondary, .destructive: content.glassEffect(.regular.interactive(), in: .capsule)
            case .quiet: content
            }
        }
    }
}

/// The round play/stop control on anything that has audio behind it.
struct PlayButton: View {
    let isPlaying: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isPlaying {
                    WaveBars(count: 4, height: 16, tint: Palette.teal)
                } else {
                    Image(systemName: "play.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                }
            }
            .frame(width: 44, height: 44)
            .background(isPlaying ? Palette.teal.opacity(0.18) : Palette.fillStrong, in: Circle())
            .animation(.smooth(duration: 0.2), value: isPlaying)
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityLabel(isPlaying ? "Stop audio" : label)
    }
}

/// A setting: a switch with a one-line explanation under it.
struct ToggleRow: View {
    let title: String
    let systemImage: String
    let caption: String
    @Binding var isOn: Bool
    var tint: Color = Palette.cloud

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(isOn: $isOn) {
                Label(title, systemImage: systemImage)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(tint)
            .frame(minHeight: 44)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A glass segmented switcher with a sliding highlight (it only fades when Reduce Motion is on).
struct EchoSegmented<Value: Hashable>: View {
    struct Segment: Identifiable {
        let value: Value
        let title: String
        /// A count shown as a small badge on the segment, like an unread count (nothing when nil).
        var badge: Int? = nil
        /// What VoiceOver says after the title ("15 open").
        var spoken: String? = nil
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// "Title 15": one run of text, so the number sits on the title's own line and baseline.
    private func label(_ segment: Segment, selected: Bool) -> some View {
        let title = Text(segment.title)
        let text = segment.badge.map { title + Text(" \($0)").foregroundStyle(Palette.teal) } ?? title
        return text
            .font(.echoLabel)
            .monospacedDigit()
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .minimumScaleFactor(0.8)
    }

    var body: some View {
        // With very large text the choices wrap into rows of two, instead of being cut short ("Promis…").
        let layout = typeSize.isAccessibilitySize ? AnyLayout(TwoColumnLayout(spacing: Spacing.xs)) : AnyLayout(HStackLayout(spacing: Spacing.xs))
        layout {
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button { selection = segment.value } label: {
                    // The count is part of the same line of text, in the same size and on the same baseline, only in teal ("Promises 15").
                    label(segment, selected: selected)
                        .frame(height: typeSize.isAccessibilitySize ? nil : 22, alignment: .center)   // the same height with or without a badge, so labels line up
                        .foregroundStyle(selected ? Palette.textPrimary : Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if selected {
                                Capsule().fill(Palette.fillStrong).matchedGeometryEffect(id: "highlight", in: highlight)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(segment.title)
                .accessibilityValue(segment.spoken ?? "")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(Spacing.xs)
        .glassEffect(.regular, in: typeSize.isAccessibilitySize ? AnyShape(RoundedRectangle(cornerRadius: 28, style: .continuous)) : AnyShape(Capsule()))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
    }
}

/// Lays children out in two equal columns, as many rows as it takes.
struct TwoColumnLayout: Layout {
    var spacing: CGFloat = Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let cell = (width - spacing) / 2
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }
        let rows = stride(from: 0, to: heights.count, by: 2).map { heights[$0..<min($0 + 2, heights.count)].max() ?? 0 }
        return CGSize(width: width, height: rows.reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cell = (bounds.width - spacing) / 2
        var y = bounds.minY
        for start in stride(from: 0, to: subviews.count, by: 2) {
            let row = subviews[start..<min(start + 2, subviews.count)]
            let height = row.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }.max() ?? 0
            for (offset, subview) in row.enumerated() {
                subview.place(at: CGPoint(x: bounds.minX + CGFloat(offset) * (cell + spacing), y: y), proposal: ProposedViewSize(width: cell, height: height))
            }
            y += height + spacing
        }
    }
}

/// "Show all 15" / "Show fewer" under a capped list. Draws nothing when everything is already visible.
struct ShowMoreButton: View {
    let total: Int
    let limit: Int
    @Binding var isExpanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if total > limit {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { isExpanded.toggle() }
            } label: {
                Text(isExpanded ? "Show fewer" : "Show all \(total)")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.teal)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EchoPressStyle())
        }
    }
}
