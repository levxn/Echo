import SwiftUI

/// Commitments heard today, found on the phone with plain rules (no model, nothing sent): a checklist with
/// who and when where known, and the source audio one tap away.
struct PromisesSection: View {
    let promises: [Promise]
    let model: PipelineModel
    let player: ChunkPlayer

    @AppStorage("echo.promiseDone") private var doneRaw = ""
    @State private var showAll = false
    @State private var expanded: String?

    private static let collapsedCount = 5
    private var done: Set<String> { Set(doneRaw.split(separator: "\n").map(String.init)) }
    private var visible: [Promise] { Capped.visible(promises, limit: Self.collapsedCount, showAll: showAll) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Commitments", meta: "\(promises.count) heard · \(promises.filter { done.contains($0.id) }.count) done")
            Label("Found on this phone, nothing sent. Echo doesn't tell speakers apart, so these are commitments heard, not only yours.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: Spacing.sm) {
                ForEach(visible) { promise in
                    PromiseRow(promise: promise, isDone: done.contains(promise.id), isExpanded: expanded == promise.id,
                               playing: player.playingID == promise.chunkID,
                               onToggleDone: { toggleDone(promise.id) },
                               onToggleExpand: { withAnimation(.smooth(duration: 0.25)) { expanded = expanded == promise.id ? nil : promise.id } },
                               onPlay: { if let chunk = model.record(id: promise.chunkID) { player.toggle(chunk) } })
                }
            }
            ShowMoreButton(total: promises.count, limit: Self.collapsedCount, isExpanded: $showAll)
        }
    }

    private func toggleDone(_ id: String) {
        var set = done
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        doneRaw = set.sorted().joined(separator: "\n")
    }
}

private struct PromiseRow: View {
    let promise: Promise
    let isDone: Bool
    let isExpanded: Bool
    let playing: Bool
    let onToggleDone: () -> Void
    let onToggleExpand: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Button(action: onToggleDone) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isDone ? Palette.teal : Palette.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")

                Button(action: onToggleExpand) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(promise.sentence)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isDone ? Palette.textSecondary : Palette.textPrimary)
                            .strikethrough(isDone, color: Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        FlowLayout {
                            if promise.kind == .reminder { Chip(text: "Reminder", icon: "bell.fill", tint: Palette.amber, size: .compact) }
                            if let due = promise.due { Chip(text: due, icon: "clock", tint: Palette.teal, size: .compact) }
                            if let to = promise.toWhom { Chip(text: "to \(to)", icon: "person.fill", tint: Palette.blue, size: .compact) }
                            Text(promise.timeLabel)
                                .font(Font.echoMeta.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                PlayButton(isPlaying: playing, label: "Play the audio from \(promise.timeLabel)", action: onPlay)
            }
            if isExpanded, let context = promise.context {
                Text("Just before: “\(context)”")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 52)
                    .transition(.opacity)
            }
        }
        .echoRow(horizontal: Spacing.sm, vertical: 0)
        .opacity(isDone ? 0.7 : 1)
    }
}
