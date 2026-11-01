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
            Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 44, height: 44)
                .background(Palette.fillStrong, in: Circle())
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
        var id: Value { value }
    }

    let segments: [Segment]
    @Binding var selection: Value

    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(segments) { segment in
                let selected = segment.value == selection
                Button { selection = segment.value } label: {
                    Text(segment.title)
                        .font(.echoLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(Spacing.xs)
        .glassEffect(.regular, in: .capsule)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: selection)
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
