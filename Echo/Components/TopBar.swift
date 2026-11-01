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

/// One slim header on every tab. Left: your profile, then "ECHO" over where you are. Right: three glanceable indicators in
/// one glass capsule (is the watch there, is the cloud allowed, everything stays on this phone). It has no backdrop of
/// its own: content scrolls under it and the system fades it out.
struct EchoTopBar: View {
    let title: String
    let profile: ProfileStore
    let watch: HeaderStatus.Indicator
    let cloud: HeaderStatus.Indicator
    let listening: Bool
    let onProfile: () -> Void
    let onWatch: () -> Void
    let onCloud: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.md) {
            Button(action: onProfile) {
                AvatarView(profile: profile)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(EchoPressStyle())
            .accessibilityLabel(profile.name.isEmpty ? "Profile" : "Profile, \(profile.name)")
            .accessibilityHint("Opens your profile")

            VStack(alignment: .leading, spacing: 0) {
                Text("ECHO")
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(Palette.teal)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
            }

            Spacer(minLength: Spacing.sm)

            HStack(spacing: 0) {
                indicator(watch, action: onWatch, pulse: listening)
                indicator(cloud, action: onCloud)
                indicator(HeaderStatus.lock, action: onProfile)
            }
            .padding(.horizontal, Spacing.xs)
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
