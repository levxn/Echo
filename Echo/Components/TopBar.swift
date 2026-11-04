import SwiftUI

extension HeaderStatus.Tint {
    var color: Color {
        switch self {
        case .teal: Palette.teal
        case .amber: Palette.amber
        case .violet: Palette.cloud
        }
    }
}

/// The round profile button: initials on tinted glass with a fine ring in the profile colour, or a person glyph until a
/// name is set.
struct AvatarView: View {
    let profile: ProfileStore
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            if profile.initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            } else {
                Text(profile.initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.tint(profile.color.opacity(0.4)), in: .circle)
        .overlay { Circle().strokeBorder(profile.color.opacity(0.85), lineWidth: size > 60 ? 2.5 : 1.5) }
        .accessibilityHidden(true)
    }
}

/// One slim header on every tab: "ECHO" in the middle, and one indicator on the right (is the watch there, is it listening). It has no
/// backdrop of its own: content scrolls under it and the system fades it out. The tab bar already names the page, so the header doesn't.
struct EchoTopBar: View {
    /// The page, read out by VoiceOver after the name.
    let title: String
    let watch: HeaderStatus.Indicator
    let listening: Bool
    let onWatch: () -> Void
    /// When a page inside a tab is open (a section of You), the standard back button takes the empty place on the left.
    var onBack: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wide-set capitals in Avenir Next, plain white. (A system font that ships with iOS, so nothing is bundled.)
    private static let tracking: CGFloat = 6
    private static let slot: CGFloat = 52

    var body: some View {
        HStack(spacing: 0) {
            // Same width as the indicator on the other side, so the name sits exactly in the middle.
            Group {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(width: Self.slot, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(EchoPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .accessibilityLabel("Back")
                } else {
                    Color.clear.frame(width: Self.slot, height: 44)
                }
            }
            .frame(width: Self.slot, height: 44)
            Spacer(minLength: 0)
            Text("ECHO")
                .font(.custom("AvenirNext-DemiBold", size: 22, relativeTo: .title3))
                .tracking(Self.tracking)
                .padding(.leading, Self.tracking)   // the spacing after the last letter would otherwise push the word left of centre
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Echo, \(title)")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            indicator(watch, action: onWatch, pulse: listening)
                .frame(width: Self.slot)
                .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.sm)
    }

    private func indicator(_ i: HeaderStatus.Indicator, action: @escaping () -> Void, pulse: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: i.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(i.tint.color)
                .symbolEffect(.variableColor.iterative, isActive: pulse && !reduceMotion)
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityLabel(i.label)
    }
}
