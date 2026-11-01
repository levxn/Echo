import SwiftUI

/// The one way to head a section. `.headline` is a section title with optional trailing content (a count, a status);
/// `.overline` is the small uppercase label above a group of rows. Both are announced as headings by VoiceOver.
struct SectionHeader<Trailing: View>: View {
    enum Style { case headline, overline }

    let title: String
    var style: Style = .headline
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(style == .headline ? .echoSection : Font.echoMeta.weight(.semibold))
                .textCase(style == .overline ? .uppercase : nil)
                .foregroundStyle(style == .headline ? Palette.textPrimary : Palette.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String, style: Style = .headline) {
        self.init(title: title, style: style) { EmptyView() }
    }
}

extension SectionHeader where Trailing == Text {
    /// A header with a short count or note on the right ("4 conversations").
    init(_ title: String, meta: String, style: Style = .headline) {
        self.init(title: title, style: style) {
            Text(meta).font(.footnote).monospacedDigit().foregroundStyle(Palette.textSecondary)
        }
    }
}
