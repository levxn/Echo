import SwiftUI

/// The top of Today once there is a day to show: three numbers and the next thing you said you would do.
struct TodayHero: View {
    let model: PipelineModel
    let promises: [Promise]
    /// The same number as on the Promises tab below.
    let openPromises: Int
    let conversations: Int
    let onOpenPromises: () -> Void
    var onOpenTimeline: () -> Void = {}

    @Environment(VoiceBookModel.self) private var voices
    @AppStorage(DayWiper.promiseDoneKey) private var doneRaw = ""
    @Environment(\.dynamicTypeSize) private var typeSize

    private var snapshot: WidgetSnapshot {
        WidgetSnapshotBuilder.make(promises: promises, reminders: [:], done: Set(doneRaw.split(separator: "\n").map(String.init)),
                                   myVoice: voices.me?.id, momentsToday: model.todayChunks.filter { $0.status == .stored }.count,
                                   listening: false, now: model.now())
    }

    var body: some View {
        let snap = snapshot
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Three equal tiles. With very large text they stack, so a label like "Conversations" is never squeezed.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.sm))
                                                      : AnyLayout(HStackLayout(spacing: Spacing.sm))
            layout {
                tile(snap.momentsToday, "Moments", symbol: "waveform", tint: Palette.blue)
                tile(conversations, conversations == 1 ? "Conversation" : "Conversations", symbol: "bubble.left.and.bubble.right.fill",
                     tint: Palette.violet, hint: "Opens the timeline", action: onOpenTimeline)
                tile(openPromises, "Open promises", symbol: "checkmark.circle.fill", tint: Palette.teal,
                     hint: "Opens your promises", action: onOpenPromises)
            }
            .fixedSize(horizontal: false, vertical: true)   // the three tiles are always the same height
            if let next = snap.items.first {
                Button(action: onOpenPromises) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Image(systemName: "checkmark.circle")
                            .font(.title3)
                            .foregroundStyle(Palette.teal)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            Text("Next up")
                                .font(Font.echoMeta.weight(.medium))
                                .foregroundStyle(Palette.textSecondary)
                            Text(next.text)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            if let due = next.due {
                                Text(due)
                                    .font(Font.echoMeta)
                                    .foregroundStyle(Palette.teal)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(Spacing.md)
                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens your promises")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    /// One of the three numbers: an icon, the number, and what it counts, on a softly tinted tile.
    @ViewBuilder
    private func tile(_ value: Int, _ label: String, symbol: String, tint: Color, hint: String? = nil, action: (() -> Void)? = nil) -> some View {
        let content = VStack(alignment: .leading, spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text("\(value)")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)   // one line, so a word is never broken in two
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 10)
        .padding(.vertical, Spacing.md)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).strokeBorder(tint.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
        if let action {
            Button(action: action) { content.contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)) }
                .buttonStyle(EchoPressStyle())
                .accessibilityHint(hint ?? "")
        } else {
            content
        }
    }
}
