import SwiftUI

/// A small tinted capsule: a keyword, a due date, a person, a status.
struct Chip: View {
    enum Size { case regular, compact }

    let text: String
    var icon: String?
    var tint: Color = Palette.teal
    var size: Size = .regular
    /// Shows a moving equalizer in place of the icon (audio is playing).
    var wave = false

    var body: some View {
        Group {
            if wave {
                HStack(spacing: Spacing.xs) { WaveBars(count: 3, height: 11, tint: tint); Text(text) }
            } else if let icon { Label(text, systemImage: icon) } else { Text(text) }
        }
        .font(size == .regular ? Font.echoMeta.weight(.medium) : Font.echoMicro.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, size == .regular ? Spacing.snug : Spacing.sm)
        .padding(.vertical, size == .regular ? 5 : 3)
        .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Lays children out left to right and wraps to a new line when the row is full, so tags and keywords never clip.
struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.tight
    var lineSpacing: CGFloat = Spacing.tight

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        FlowLayout.arrange(sizes: subviews.map { $0.sizeThatFits(.unspecified) }, maxWidth: proposal.width ?? .infinity,
                           spacing: spacing, lineSpacing: lineSpacing).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = FlowLayout.arrange(sizes: subviews.map { $0.sizeThatFits(.unspecified) }, maxWidth: bounds.width,
                                        spacing: spacing, lineSpacing: lineSpacing)
        for (subview, point) in zip(subviews, layout.positions) {
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    /// The line-breaking rule, free of SwiftUI so it can be tested: an item that does not fit on the current line
    /// starts a new one, and an item wider than the row sits alone on its line.
    nonisolated static func arrange(sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat, lineSpacing: CGFloat)
        -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (positions, CGSize(width: sizes.isEmpty ? 0 : min(widest, maxWidth.isFinite ? maxWidth : widest), height: sizes.isEmpty ? 0 : y + lineHeight))
    }
}
