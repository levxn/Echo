import SwiftUI

/// A small coloured circle with a voice's initial: who said it.
struct VoiceDot: View {
    let voice: Voice
    var size: CGFloat = 22

    var body: some View {
        let tint = ProfileStore.palette[voice.colorIndex % ProfileStore.palette.count]
        Text(voice.initial)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(Palette.textPrimary)
            .frame(width: size, height: size)
            .background(tint.opacity(0.35), in: Circle())
            .overlay(Circle().strokeBorder(tint, lineWidth: 1.2))
            .accessibilityLabel(voice.display)
    }
}

/// The voices the phone has told apart, on the People tab: tap one to name it or say it is you.
struct VoicesStrip: View {
    let model: VoiceBookModel
    let chunks: [ChunkRecord]
    let player: ChunkPlayer
    @State private var selected: Voice?

    var body: some View {
        if !model.voices.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader("Voices", meta: "\(model.voices.count) told apart", style: .overline)
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(model.voices) { voice in
                            Button { selected = voice } label: {
                                HStack(spacing: Spacing.sm) {
                                    VoiceDot(voice: voice, size: 26)
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(voice.isMe ? "\(voice.display) (you)" : voice.display)
                                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                                            .foregroundStyle(Palette.textPrimary)
                                        let moments = chunks.filter { $0.speakerId == voice.id && $0.status == .stored }.count
                                        Text("\(moments) moment\(moments == 1 ? "" : "s")")
                                            .font(.caption2)
                                            .foregroundStyle(Palette.textSecondary)
                                    }
                                }
                                .padding(.horizontal, Spacing.md)
                                .frame(minHeight: 48)
                            }
                            .buttonStyle(EchoPressStyle())
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .accessibilityHint("Name this voice, or say it is you")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                if let guess = model.suggestedMe {
                    HStack(spacing: Spacing.md) {
                        VoiceDot(voice: guess, size: 28)
                        Text("\(guess.display) is heard most. Is that you?")
                            .font(.footnote)
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Button("That's me") { Task { await model.setMe(guess.id) } }
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.teal)
                            .frame(minHeight: 44)
                    }
                    .echoRow(vertical: Spacing.xs)
                } else {
                    Text("Echo tells voices apart on this phone, from the audio. Name them so it can say who said what.")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sheet(item: $selected) { voice in
                VoiceSheet(model: model, voiceID: voice.id, chunks: chunks, player: player)
            }
        }
    }
}

/// One voice: its name, whether it is you, other voices it may be, and what it said.
struct VoiceSheet: View {
    let model: VoiceBookModel
    let voiceID: String
    let chunks: [ChunkRecord]
    let player: ChunkPlayer

    @State private var name = ""
    @State private var loaded = false
    @State private var confirmForget = false
    @Environment(\.dismiss) private var dismiss

    private var voice: Voice? { model.voice(id: voiceID) }
    private var moments: [ChunkRecord] { chunks.filter { $0.speakerId == voiceID && $0.status == .stored }.suffix(8).reversed() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack {
                    Text("Voice")
                        .font(.echoSheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { commitName(); dismiss() }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minWidth: 44, minHeight: 44)
                }
                if let voice {
                    VStack(spacing: Spacing.lg) {
                        VoiceDot(voice: voice, size: 72)
                        TextField("Name this voice", text: $name)
                            .submitLabel(.done)
                            .onSubmit(commitName)
                            .multilineTextAlignment(.center)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(minHeight: 48)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        ToggleRow(title: "This is me", systemImage: "person.fill",
                                  caption: "Your promises are then listed as yours, and \"what did I promise?\" is about what you said.",
                                  isOn: Binding(get: { voice.isMe }, set: { on in Task { await model.setMe(on ? voice.id : nil) } }), tint: Palette.teal)
                    }
                    .frame(maxWidth: .infinity)
                    .echoCard()

                    let others = model.voices.filter { $0.id != voice.id }
                    if !others.isEmpty {
                        Menu {
                            ForEach(others) { other in
                                Button("Same as \(other.display)") { Task { await model.merge(voice.id, into: other.id); dismiss() } }
                            }
                        } label: {
                            Label("This is the same person as…", systemImage: "arrow.triangle.merge")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }

                    if !moments.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            SectionHeader("What this voice said", style: .overline)
                            ForEach(moments) { chunk in
                                HStack(alignment: .top, spacing: Spacing.md) {
                                    Text(chunk.stamp())
                                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(Palette.textPrimary)
                                        .frame(minWidth: 48, alignment: .leading)
                                        .fixedSize(horizontal: true, vertical: false)
                                    Text(chunk.transcript ?? "")
                                        .font(.subheadline)
                                        .foregroundStyle(Palette.textSecondary)
                                        .lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    PlayButton(isPlaying: player.playingID == chunk.id, label: "Play the audio from \(chunk.stamp())") { player.toggle(chunk) }
                                }
                                .echoRow()
                            }
                        }
                    }

                    EchoButton(title: "Forget this voice", systemImage: "trash", style: .destructive) { confirmForget = true }
                }
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
        .onAppear { if !loaded { name = voice?.name ?? ""; loaded = true } }
        .confirmationDialog("Forget this voice?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget the voice", role: .destructive) { Task { await model.forget(voiceID); dismiss() } }
        } message: {
            Text("Its moments stay, but they are no longer attributed to anyone. The next time it is heard it will be a new voice.")
        }
    }

    private func commitName() { Task { await model.rename(voiceID, to: name) } }
}
