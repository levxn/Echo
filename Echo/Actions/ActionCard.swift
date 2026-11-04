import SwiftUI

/// One thing to act on: what it is, when, who it concerns, the words it came from (with the audio), and the button that opens it.
struct ActionCard: View {
    let item: ActionItem
    let section: ActionsModel.Section
    let now: Date
    let place: String?
    let speakerName: String?
    let playing: Bool
    let onOpen: () -> Void
    let onPlay: () -> Void
    let onDone: () -> Void
    let onDismiss: () -> Void
    let onLater: (Date) -> Void

    private var tint: Color {
        switch item.kind {
        case .calendar: Palette.blue
        case .email, .message: Palette.teal
        case .call: Palette.teal
        case .todo, .shopping: Palette.amber
        case .waiting: Palette.violet
        }
    }

    private var when: String? { ActionFormat.when(item, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                Image(systemName: item.kind.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(item.kind.label)
                        .font(Font.echoMicro.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(tint)
                    Text(item.title)
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                menu
            }

            if when != nil || item.person != nil || !item.items.isEmpty || !item.detail.isEmpty {
                FlowLayout {
                    if let when { Chip(text: when, icon: section == .overdue ? "exclamationmark.circle.fill" : "clock", tint: section == .overdue ? Palette.rose : Palette.teal, size: .compact) }
                    if let person = item.person { Chip(text: person, icon: "person.fill", tint: Palette.blue, size: .compact) }
                    if !item.items.isEmpty { Chip(text: "\(item.items.count) items", icon: "list.bullet", tint: Palette.amber, size: .compact) }
                    if !item.detail.isEmpty, item.detail != item.person { Chip(text: item.detail, icon: "info.circle", tint: Palette.textSecondary, size: .compact) }
                }
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("“\(item.quote)”")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(["Heard \(item.timeLabel)", speakerName, place].compactMap { $0 }.joined(separator: " · "))
                        .font(Font.echoMeta.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PlayButton(isPlaying: playing, label: "Play the audio from \(item.timeLabel)", action: onPlay)
            }

            EchoButton(title: item.kind.primaryTitle, systemImage: "arrow.up.forward.app", style: .prominent, tint: tint, action: onOpen)
        }
        .echoCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ActionFormat.spoken(item, when: when))
    }

    private var menu: some View {
        Menu {
            Button("Mark done", systemImage: "checkmark.circle", action: onDone)
            Menu("Remind me later", systemImage: "clock.arrow.circlepath") {
                ForEach(ReminderOptions.options(due: nil, now: now)) { option in Button(option.title) { onLater(option.date) } }
            }
            Divider()
            Button("Not an action", systemImage: "xmark.circle", role: .destructive, action: onDismiss)
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 44, height: 44)
                .background(Palette.fillStrong, in: Circle())
        }
        .accessibilityLabel("More for \(item.title)")
    }
}

/// An action that has been dealt with: where it went, and a way back.
struct DoneActionRow: View {
    let item: ActionItem
    let via: String?
    let onMoveBack: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.teal).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textSecondary)
                    .strikethrough(true, color: Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let via { Text("Opened in \(via)").font(Font.echoMeta).foregroundStyle(Palette.textTertiary) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Move back", action: onMoveBack)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.teal)
                .frame(minWidth: 44, minHeight: 44)
        }
        .echoRow(horizontal: Spacing.md, vertical: Spacing.xs)
    }
}
