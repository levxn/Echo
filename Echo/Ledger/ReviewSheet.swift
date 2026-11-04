import SwiftUI

/// Shown when "Review before sending" is on: the exact request, and a choice.
struct ReviewSheet: View {
    let review: ReviewGate.Pending
    let onSend: () -> Void
    let onCancel: () -> Void

    @State private var showRequest = false

    private var plan: TierTwoPlan { review.plan }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text("Review before sending")
                        .font(.echoSheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text("This is exactly what will go to Muse Spark. Audio never does.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label(review.kind == .ask ? "Your question" : "Request", systemImage: "questionmark.bubble")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .textCase(.uppercase)
                    Text(plan.masking.mask(review.query))
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()

                VStack(alignment: .leading, spacing: Spacing.md) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("\(plan.snippets.count) snippets of text")
                            .font(.echoSection)
                            .foregroundStyle(Palette.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(ByteFormat.short(plan.bodyBytes)) · about \(plan.bodyBytes / 4) tokens")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text("Chosen because: \(plan.selectionReason).")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !plan.masking.isEmpty {
                        Label("\(plan.maskedCount) names are replaced with placeholders. Only the placeholders go to Muse.", systemImage: "theatermasks")
                            .font(.footnote)
                            .foregroundStyle(Palette.teal)
                    }
                    if plan.masking.hasSecrets {
                        Label("\(plan.heldBackCount) sensitive detail\(plan.heldBackCount == 1 ? "" : "s") stay\(plan.heldBackCount == 1 ? "s" : "") on this phone (\(plan.masking.secrets.summary)). Only placeholders go to Muse.", systemImage: "lock.shield.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.teal)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(plan.snippets) { snippet in
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            Text(snippet.time)
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.cloud)
                                .frame(width: 40, alignment: .leading)
                            Text(snippet.text)
                                .font(.caption)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()

                DisclosureGroup(isExpanded: $showRequest) {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        raw("Instructions (developer message)", plan.request.developer)
                        raw("Message (user)", plan.request.user)
                    }
                    .padding(.top, Spacing.sm)
                } label: {
                    Label("Show the full request", systemImage: "curlybraces")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(minHeight: 44)
                }
                .tint(Palette.textSecondary)

                Spacer(minLength: Spacing.xxl)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Spacing.sm) {
                EchoButton(title: "Send to Muse", systemImage: "paperplane.fill", style: .prominent, action: onSend)
                EchoButton(title: "Don't send", style: .quiet, action: onCancel)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.vertical, Spacing.md)
            .background(.ultraThinMaterial)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }

    private func raw(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary).textCase(.uppercase)
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoRow()
    }
}
