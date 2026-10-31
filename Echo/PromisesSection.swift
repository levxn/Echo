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
    private var visible: [Promise] { showAll ? promises : Array(promises.prefix(Self.collapsedCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text("Commitments")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Text("\(promises.count) heard · \(promises.filter { done.contains($0.id) }.count) done")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
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
            if promises.count > Self.collapsedCount {
                Button { withAnimation(.smooth(duration: 0.3)) { showAll.toggle() } } label: {
                    Text(showAll ? "Show fewer" : "Show all \(promises.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
            }
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
                        .font(.system(size: 22))
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
                        HStack(spacing: 6) {
                            if promise.kind == .reminder { tag("Reminder", icon: "bell.fill", color: Palette.amber) }
                            if let due = promise.due { tag(due, icon: "clock", color: Palette.teal) }
                            if let to = promise.toWhom { tag("to \(to)", icon: "person.fill", color: Palette.blue) }
                            Text(promise.timeLabel)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button(action: onPlay) {
                    Image(systemName: playing ? "stop.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel(playing ? "Stop audio" : "Play the audio from \(promise.timeLabel)")
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
        .padding(.horizontal, Spacing.sm)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(isDone ? 0.7 : 1)
    }

    private func tag(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}
