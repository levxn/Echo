import SwiftUI

/// "A week ago today": one line from an earlier day, found on the phone, with a way to ask about it.
struct ResurfacedCard: View {
    let item: Resurfaced
    let onAsk: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label(item.title, systemImage: "clock.arrow.circlepath")
                .font(.echoLabel)
                .foregroundStyle(Palette.blue)
            Text("“\(item.gist)”")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(item.conversations) conversation\(item.conversations == 1 ? "" : "s") · \(item.moments) moments, kept on this phone")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            EchoButton(title: "What happened that day?", systemImage: "clock.arrow.circlepath", action: onAsk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }
}
