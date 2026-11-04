import SwiftUI

/// Who this is, at the top of the You tab: a small avatar, the greeting and the name. Tapping it opens the editor (`ProfileEditSheet`).
struct ProfileCard: View {
    let profile: ProfileStore
    let onEdit: () -> Void

    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: Spacing.lg) {
                AvatarView(profile: profile, size: 60)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(profile.greeting)
                        .font(Font.echoMeta.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(profile.name.isEmpty ? "Add your name" : profile.name)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "pencil")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Palette.fillStrong, in: Circle())
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityLabel("Your profile: \(profile.name)")
        .accessibilityHint("Edit your name and colour")
    }
}

/// Edit your name and colour, in a sheet of their own.
struct ProfileEditSheet: View {
    @Bindable var profile: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xl) {
                HStack {
                    Text("Your profile")
                        .font(.echoSheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minWidth: 44, minHeight: 44)
                }
                AvatarView(profile: profile, size: 96)
                TextField("Your name", text: $profile.name)
                    .focused($nameFocused)
                    .textContentType(.givenName)
                    .submitLabel(.done)
                    .multilineTextAlignment(.center)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minHeight: 48)
                    .glassEffect(.regular.interactive(), in: .capsule)
                colourPicker
                Text("Only on this phone. No account.")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { AuroraBackground(calm: true) }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
    }

    private var colourPicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(0..<ProfileLogic.colorCount, id: \.self) { i in
                Button { profile.colorIndex = i } label: {
                    Circle()
                        .fill(ProfileStore.palette[i].gradient)
                        .frame(width: 30, height: 30)
                        .overlay {
                            if profile.colorIndex == i { Circle().strokeBorder(Palette.textPrimary, lineWidth: 2.5).padding(-4) }
                        }
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel("Colour \(i + 1)")
                .accessibilityAddTraits(profile.colorIndex == i ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
