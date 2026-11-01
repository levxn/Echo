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

/// The round profile button: initials on the profile colour, or a person glyph until a name is set.
struct AvatarView: View {
    let profile: ProfileStore
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(profile.color.gradient)
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            if profile.initials.isEmpty {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Palette.background.opacity(0.85))
            } else {
                Text(profile.initials)
                    .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.background)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// One slim bar at the top of every tab: your profile on the left, where you are in the middle, and three glanceable
/// indicators on the right (is the watch there, is the cloud allowed, everything stays on this phone).
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
        ZStack {
            Text(title)
                .font(.echoSection)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Button(action: onProfile) {
                    AvatarView(profile: profile)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel(profile.name.isEmpty ? "Profile" : "Profile, \(profile.name)")
                .accessibilityHint("Opens your profile")
                Spacer(minLength: Spacing.sm)
                HStack(spacing: 0) {
                    indicator(watch, action: onWatch, pulse: listening)
                    indicator(cloud, action: onCloud)
                    indicator(HeaderStatus.lock, action: onProfile)
                }
                .padding(.horizontal, Spacing.xs)
                .glassEffect(.regular, in: .capsule)
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.xs)
        .frame(minHeight: 52)
        // Content scrolls underneath a frosted backdrop that also covers the status bar area.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .bottom) { Rectangle().fill(Palette.stroke).frame(height: 0.5) }
                .ignoresSafeArea(edges: .top)
        }
    }

    private func indicator(_ i: HeaderStatus.Indicator, action: @escaping () -> Void, pulse: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: i.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(i.tint.color)
                .symbolEffect(.variableColor.iterative, isActive: pulse && !reduceMotion)
                .frame(width: 38, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityLabel(i.label)
    }
}
