import SwiftUI

/// Your profile: a name and a colour, kept on this phone only. No account, no login.
struct ProfileSheet: View {
    @Bindable var profile: ProfileStore
    let onOpenPrivacy: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack(alignment: .center) {
                    Text("Profile")
                        .font(.echoSheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minWidth: 44, minHeight: 44)
                }

                VStack(spacing: Spacing.lg) {
                    AvatarView(profile: profile, size: 84)
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
                    Text("Used for your greeting and the initials on your avatar. It is stored only on this phone, and there is no account or login.")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .echoCard()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader("Voice")
                    ToggleRow(title: "Speak answers to voice questions", systemImage: "speaker.wave.2.fill",
                              caption: "When you ask out loud, the answer is read back to you. Every answer also has a Read aloud button.",
                              isOn: $profile.speakVoiceAnswers, tint: Palette.teal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader("Promises")
                    ToggleRow(title: "Catch promises as I say them", systemImage: "checkmark.circle.fill",
                              caption: "When you say you will do something, your watch shows “Got it” and you can tap Keep for a reminder.",
                              isOn: $profile.catchPromises, tint: Palette.teal)
                    ToggleRow(title: "Remind me to write my journal", systemImage: "book.closed.fill",
                              caption: "A nudge at 9 pm. It says nothing about your day, and nothing is written or sent until you ask.",
                              isOn: $profile.journalReminder, tint: Palette.teal)
                    ToggleRow(title: "Morning summary of actions", systemImage: "sunrise.fill",
                              caption: "A nudge at 8 am saying how many things are waiting in Actions. It says nothing about what they are.",
                              isOn: $profile.actionsMorning, tint: Palette.teal)
                    ToggleRow(title: "Let Muse write my drafts", systemImage: "square.and.pencil",
                              caption: "When you open a message in Actions, Muse writes a better version. It only sees the moment, with passwords, numbers, emails and phone numbers replaced by placeholders, and your words go back in on this phone.",
                              isOn: $profile.museDrafts, tint: Palette.cloud)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    SectionHeader("Where your data lives")
                    fact("lock.fill", Palette.teal, "On this phone", "Transcripts, audio and search never leave it. Audio is never sent anywhere.")
                    fact("cloud.fill", Palette.cloud, "Only when you ask a broad question",
                         "A few text snippets go to Muse Spark, and you can review each request before it is sent.")
                    EchoButton(title: "Privacy settings", systemImage: "lock.shield.fill") {
                        dismiss()
                        onOpenPrivacy()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { AuroraBackground(calm: true) }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private var colourPicker: some View {
        HStack(spacing: Spacing.md) {
            ForEach(0..<ProfileLogic.colorCount, id: \.self) { i in
                Button { profile.colorIndex = i } label: {
                    Circle()
                        .fill(ProfileStore.palette[i].gradient)
                        .frame(width: 32, height: 32)
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
    }

    private func fact(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Text(detail).font(.footnote).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
