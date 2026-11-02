import SwiftUI
import UIKit

/// Muse writes the message that keeps a promise. You choose the tone and whether it is a text or an email, see exactly what
/// would be sent, and copy or share the result.
struct DraftSheet: View {
    let promise: Promise
    let chunks: [ChunkRecord]
    @Environment(DraftModel.self) private var drafts
    @Environment(LedgerModel.self) private var ledger
    @Environment(\.dismiss) private var dismiss

    @State private var tone = DraftTone.friendly
    @State private var channel = DraftChannel.text
    @State private var copied = false

    /// While a draft request waits for approval, the review is shown here instead of the form.
    private var pendingReview: ReviewGate.Pending? { ledger.gate.pending.flatMap { $0.kind == .draft ? $0 : nil } }

    var body: some View {
        if let review = pendingReview {
            ReviewSheet(review: review, onSend: { ledger.gate.approve() }, onCancel: { ledger.gate.cancel() })
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack {
                    Text("Draft a message")
                        .font(.echoSheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Done") { drafts.reset(); dismiss() }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minWidth: 44, minHeight: 44)
                }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader("The promise", style: .overline)
                    Text(promise.sentence)
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()

                switch drafts.state {
                case .idle, .cloudOff, .failed: options
                case .working(let plan): working(plan)
                case .ready(let ready): result(ready)
                }

                if case .cloudOff = drafts.state {
                    Label("Cloud is off, so Muse can't write it. Turn it back on in Privacy.", systemImage: "cloud.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                }
                if case .failed(let message) = drafts.state {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Palette.amber)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground(calm: true) }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onAppear { drafts.reset() }
        .task {
            // Dev hook: `-draft-run` writes the draft as soon as the sheet opens (screenshots).
            if ProcessInfo.processInfo.arguments.contains("-draft-run") {
                await drafts.generate(for: promise, tone: tone, channel: channel, chunks: chunks)
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            EchoSegmented(segments: DraftChannel.allCases.map { .init(value: $0, title: $0.title) }, selection: $channel)
            EchoSegmented(segments: DraftTone.allCases.map { .init(value: $0, title: $0.title) }, selection: $tone)
            EchoButton(title: "Write it with Muse", systemImage: "sparkles", style: .prominent) {
                Task { await drafts.generate(for: promise, tone: tone, channel: channel, chunks: chunks) }
            }
            Label(ledger.reviewBeforeSend ? "You will see exactly what is sent first. Only this moment and the line before it go to Muse, as text."
                                          : "Only this moment and the line before it go to Muse, as text, and it is logged in your Privacy Ledger.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func working(_ plan: TierTwoPlan) -> some View {
        HStack(spacing: Spacing.md) {
            ProgressView().tint(Palette.cloud)
            Text(drafts.isStub ? "Preparing a stub preview. Nothing is sent."
                               : "Sending \(plan.snippets.count) snippet\(plan.snippets.count == 1 ? "" : "s") (\(ByteFormat.short(plan.bodyBytes))) to Muse Spark…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }

    private func result(_ ready: DraftModel.Ready) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label(ready.isStub ? "Stub preview · no API key" : "Written by Muse Spark", systemImage: ready.isStub ? "testtube.2" : "cloud.fill")
                .font(.echoLabel)
                .foregroundStyle(ready.isStub ? Palette.amber : Palette.cloud)
            if !ready.draft.subject.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Subject").font(.caption).foregroundStyle(Palette.textSecondary)
                    Text(ready.draft.subject).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary).textSelection(.enabled)
                }
            }
            Text(ready.draft.body)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text("Check it before you send it: Muse only knew what was said in that moment.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
            FlowLayout {
                Button {
                    UIPasteboard.general.string = ready.draft.text
                    copied = true
                    Haptics.success()
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
                ShareAnswerButton(text: ready.draft.text)
                Button { drafts.reset(); copied = false } label: {
                    Label("Write another", systemImage: "arrow.clockwise")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }
}
