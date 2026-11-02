import SwiftUI

/// Who the day's conversations mention: tap a name to see the moments it came up in, the commitments that involve
/// them, and to ask about them. All of it is worked out on this phone.
struct PeopleSection: View {
    let people: [Person]
    let promises: [Promise]
    let model: PipelineModel
    let player: ChunkPlayer
    let onAsk: (String) -> Void
    /// "Not a person": the recognizer heard a word that isn't a name.
    let onIgnore: (Person) -> Void

    @State private var expanded: String?
    @State private var showAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(VoiceBookModel.self) private var voices

    private static let collapsedCount = 6
    private var visible: [Person] { Capped.visible(people, limit: Self.collapsedCount, showAll: showAll) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VoicesStrip(model: voices, chunks: model.chunks, player: player)
            SectionHeader("People", meta: "\(people.count) named")
            Label("Found on this phone, nothing sent. Names come from speech recognition, which can get one wrong or miss one. This lists people mentioned or spoken to; Voices above is who was talking.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Spacing.sm) {
                ForEach(visible) { person in
                    PersonRow(person: person, isExpanded: expanded == person.id,
                              moments: person.momentIDs.compactMap { model.record(id: $0) },
                              promises: PeopleIndex.promises(for: person, in: promises), player: player,
                              onToggle: { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { expanded = expanded == person.id ? nil : person.id } },
                              onAsk: { onAsk("What did \(person.name) say?") },
                              onIgnore: { onIgnore(person) })
                }
            }
            ShowMoreButton(total: people.count, limit: Self.collapsedCount, isExpanded: $showAll)
        }
        .task {
            // Dev hook: `-people-open` opens the first person (screenshots).
            guard ProcessInfo.processInfo.arguments.contains("-people-open"), expanded == nil else { return }
            expanded = people.first?.id
        }
        .onChange(of: people.first?.id) { _, id in
            if ProcessInfo.processInfo.arguments.contains("-people-open"), expanded == nil { expanded = id }
        }
    }
}

private struct PersonRow: View {
    let person: Person
    let isExpanded: Bool
    let moments: [ChunkRecord]
    let promises: [Promise]
    let player: ChunkPlayer
    let onToggle: () -> Void
    let onAsk: () -> Void
    let onIgnore: () -> Void

    private static let momentLimit = 4
    @State private var showAllMoments = false

    private var tint: Color { ProfileStore.palette[abs(person.id.hashValue) % ProfileStore.palette.count] }
    private var span: String { person.firstLabel == person.lastLabel ? person.firstLabel : "\(person.firstLabel) to \(person.lastLabel)" }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Button(action: onToggle) {
                HStack(spacing: Spacing.md) {
                    Text(String(person.name.prefix(1)).uppercased())
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(tint.opacity(0.35), in: Circle())
                        .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(person.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(person.count) moment\(person.count == 1 ? "" : "s") · \(span)" + (person.count == 1 ? " · heard once" : ""))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isExpanded ? "Hides what was said" : "Shows what was said")

            if isExpanded {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if !promises.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            SectionHeader("Commitments", style: .overline)
                            ForEach(promises) { promise in
                                Label(promise.sentence, systemImage: "checkmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        SectionHeader("Where they came up", style: .overline)
                        ForEach(Capped.visible(moments, limit: Self.momentLimit, showAll: showAllMoments)) { chunk in
                            PersonMoment(chunk: chunk, terms: person.words, player: player)
                        }
                        ShowMoreButton(total: moments.count, limit: Self.momentLimit, isExpanded: $showAllMoments)
                    }
                    EchoButton(title: "Ask about \(person.name.split(separator: " ").first.map(String.init) ?? person.name)",
                               systemImage: "sparkles", action: onAsk)
                    EchoButton(title: "Not a person", systemImage: "eye.slash", style: .quiet, action: onIgnore)
                        .accessibilityHint("Hides this name. Use it when speech recognition heard a word that isn't a name")
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

/// One moment that mentions the person: when, the words with their name picked out, and a play button.
private struct PersonMoment: View {
    let chunk: ChunkRecord
    let terms: [String]
    let player: ChunkPlayer

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(chunk.stamp())
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(minWidth: 48, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            Text(Highlighter.attributed(chunk.transcript ?? "", terms: terms, highlight: Palette.teal, base: Palette.textSecondary))
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            PlayButton(isPlaying: player.playingID == chunk.id, label: "Play the audio from \(chunk.stamp())") { player.toggle(chunk) }
        }
        .accessibilityElement(children: .contain)
    }
}
