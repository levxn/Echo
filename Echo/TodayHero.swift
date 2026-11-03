import SwiftUI

/// The top of Today once there is a day to show: three numbers and the next thing you said you would do.
struct TodayHero: View {
    let model: PipelineModel
    let promises: [Promise]
    /// The same number as on the Promises tab below.
    let openPromises: Int
    let conversations: Int
    let onOpenPromises: () -> Void

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
            // With very large text the three numbers stack, so a label like "conversations" is never squeezed.
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))
                                                      : AnyLayout(HStackLayout(spacing: 0))
            layout {
                stat(snap.momentsToday, "moments")
                stat(conversations, "conversations")
                stat(openPromises, openPromises == 1 ? "promise open" : "promises open")
            }
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

    private func stat(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text("\(value)")
                .font(.echoScreenTitle)
                .monospacedDigit()
                .foregroundStyle(Palette.accentGradient)
                .contentTransition(.numericText())
            Text(label)
                .font(Font.echoMeta)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
