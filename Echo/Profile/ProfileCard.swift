import SwiftUI

/// Who this is: a name and a colour, kept on this phone only. No account, no login. The top of the You tab.
struct ProfileCard: View {
    @Bindable var profile: ProfileStore
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: Spacing.lg) {
            HStack(spacing: Spacing.lg) {
                AvatarView(profile: profile, size: 72)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(profile.greeting)
                        .font(Font.echoMeta.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    TextField("Your name", text: $profile.name)
                        .focused($nameFocused)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            colourPicker
            Text("Your name and colour are used for the greeting and your initials. They are stored only on this phone: there is no account or login.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    private var colourPicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<ProfileLogic.colorCount, id: \.self) { i in
                Button { profile.colorIndex = i } label: {
                    Circle()
                        .fill(ProfileStore.palette[i].gradient)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if profile.colorIndex == i {
                                Circle().strokeBorder(Palette.textPrimary, lineWidth: 2.5).padding(-4)
                            }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel("Colour \(i + 1)")
                .accessibilityAddTraits(profile.colorIndex == i ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
