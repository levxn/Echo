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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Review before sending")
                        .font(.system(.title, design: .rounded, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    Text("This is exactly what will go to Muse Spark. Audio never does.")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label(review.kind == .digest ? "Request" : "Your question", systemImage: "questionmark.bubble")
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
                    HStack {
                        Text("\(plan.snippets.count) snippets of text")
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Spacer()
                        Text("\(ByteFormat.short(plan.bodyBytes)) · about \(plan.bodyBytes / 4) tokens")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .foregroundStyle(Palette.textPrimary)
                    Text("Chosen because: \(plan.selectionReason).")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !plan.masking.isEmpty {
                        Label("\(plan.maskedCount) names are replaced with placeholders. Only the placeholders go to Muse.", systemImage: "theatermasks")
                            .font(.footnote)
                            .foregroundStyle(Palette.teal)
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
                Button(action: onSend) {
                    Label("Send to Muse", systemImage: "paperplane.fill")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.tint(Palette.cloud.opacity(0.45)).interactive(), in: .capsule)
                Button(action: onCancel) {
                    Text("Don't send")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
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
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
