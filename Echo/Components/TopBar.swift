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

/// One slim header on every tab. Left: the Echo wordmark with the app's mark in front of it. Right: three glanceable indicators in
/// one glass capsule (is the watch there, is the cloud allowed, everything stays on this phone). It has no backdrop of
/// its own: content scrolls under it and the system fades it out. The tab bar already names the page, so the header doesn't.
struct EchoTopBar: View {
    /// The page, read out by VoiceOver after the name.
    let title: String
    let watch: HeaderStatus.Indicator
    let cloud: HeaderStatus.Indicator
    let listening: Bool
    let onWatch: () -> Void
    let onCloud: () -> Void
    let onLock: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = -0.7

    private static let wordmarkFont = Font.system(size: 30, weight: .black, design: .rounded)

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.xs) {
                EchoLogo(height: 13, frame: LaunchChoreography.reducedFrame(at: 0))
                    .frame(width: 30, height: 30)
                wordmark
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Echo, \(title)")
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: Spacing.sm)

            HStack(spacing: 0) {
                indicator(watch, action: onWatch, pulse: listening)
                indicator(cloud, action: onCloud)
                indicator(HeaderStatus.lock, action: onLock)
            }
            .padding(.horizontal, Spacing.xs)
            .glassEffect(.regular, in: .capsule)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xs)
        .padding(.bottom, Spacing.sm)
    }

    /// "Echo" in heavy rounded type, in the colours of the app's aurora, with one slow glint across it when it first appears.
    private var wordmark: some View {
        Text("Echo")
            .font(Self.wordmarkFont)
            .tracking(-0.6)
            .foregroundStyle(LinearGradient(colors: [Palette.teal, Palette.blue, Palette.violet], startPoint: .leading, endPoint: .trailing))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.55)
                        .offset(x: sweep * geo.size.width)
                }
                .mask { Text("Echo").font(Self.wordmarkFont).tracking(-0.6) }
                .allowsHitTesting(false)
            }
            .fixedSize()
            .onAppear {
                guard !reduceMotion, sweep < 0 else { return }
                withAnimation(.easeInOut(duration: 1.8).delay(0.8)) { sweep = 1.2 }
            }
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
