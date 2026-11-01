import SwiftUI

extension View {
    /// A row sitting on a card: one radius and one fill everywhere.
    func echoRow(horizontal: CGFloat = Spacing.md, vertical: CGFloat = Spacing.md, fill: Color = Palette.fill) -> some View {
        self
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }
}

/// A card shown where there is nothing yet, and what to do about it.
struct EmptyState: View {
    let icon: String
    var tint: Color = Palette.blue
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .echoCard(padding: Spacing.xl)
        .accessibilityElement(children: .combine)
    }
}
