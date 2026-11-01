import SwiftUI

/// A structured answer from Muse Spark (or the labeled stub), with exactly what was sent.
struct CloudAnswerCard: View {
    let result: CloudResult
    var expandSent = false
    let player: ChunkPlayer
    /// Finds the moment on this phone a citation points at.
    let chunkFor: (CloudItem) -> ChunkRecord?

    private var isStub: Bool { result.response.isStub }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            RouteStrip(active: .cloud)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label(isStub ? "Stub preview · no API key" : "Answered by Muse Spark",
                      systemImage: isStub ? "testtube.2" : "cloud.fill")
                    .font(.echoLabel)
                    .foregroundStyle(isStub ? Palette.amber : Palette.cloud)
                Text(result.decision.reason)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(result.answer.answer)
                .font(.echoAnswer)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ReadAloudButton(text: result.answer.answer)

            // The privacy proof comes first, right under the answer, so it is on screen without scrolling.
            SentDisclosure(plan: result.plan, isStub: isStub, expand: expandSent).id("sentPanel")

            if !result.answer.items.isEmpty {
                VStack(spacing: Spacing.sm) {
                    ForEach(result.answer.items) { ItemRow(item: $0, chunk: chunkFor($0), player: player) }
                }
                .id("items")
            }

            Text(footer)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    private var footer: String {
        if isStub { return "Stub: nothing was sent. Run Tools/set_api_key.sh to connect Muse Spark." }
        let r = result.response
        return "\(r.model) · \(r.promptTokens) in / \(r.completionTokens) out tokens · \(String(format: "%.1f", r.latencyMs / 1000)) s · Logged in your Privacy Ledger"
    }
}

/// The time a citation came from; with its moment found on this phone, it plays the audio.
struct SourcePlayChip: View {
    let label: String
    let chunk: ChunkRecord?
    let player: ChunkPlayer
    var tint: Color = Palette.cloud

    private var playing: Bool { chunk.map { player.playingID == $0.id } ?? false }

    var body: some View {
        if let chunk {
            Button { player.toggle(chunk) } label: {
                Chip(text: label, icon: playing ? "stop.fill" : "play.fill", tint: tint)
                    .monospacedDigit()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(EchoPressStyle())
            .accessibilityLabel(playing ? "Stop audio" : "Play the audio from \(label)")
        } else if !label.isEmpty {
            Text(label)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}

private struct ItemRow: View {
    let item: CloudItem
    let chunk: ChunkRecord?
    let player: ChunkPlayer
    @State private var showQuote = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            content
            if showQuote, let transcript = chunk?.transcript {
                Text("Heard at \(item.sourceTime): “\(transcript)”")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .echoRow()
        .contentShape(Rectangle())
        .onTapGesture { toggleQuote() }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: chunk == nil ? "" : (showQuote ? "Hide what was said" : "Show what was said")) { toggleQuote() }
    }

    private func toggleQuote() {
        guard chunk != nil else { return }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { showQuote.toggle() }
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                if !item.when.isEmpty { Chip(text: item.when, icon: "clock", tint: Palette.cloud) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SourcePlayChip(label: item.sourceTime, chunk: chunk, player: player)
        }
    }
}

/// The exact text that left (or, for the stub, would have left) the phone.
struct SentDisclosure: View {
    let plan: TierTwoPlan
    let isStub: Bool
    /// Lets the demo driver open the panel from outside; a tap toggles it as usual.
    var expand = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: Spacing.md) {
                    Image(systemName: isStub ? "eye" : "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text(isStub ? "What would be sent" : "What left your phone")
                            .font(.echoLabel)
                            .foregroundStyle(Palette.textPrimary)
                        Text("\(plan.snippets.count) snippets · \(ByteFormat.short(plan.bodyBytes)) · 0 bytes of audio"
                             + (plan.maskedCount > 0 ? " · \(plan.maskedCount) names masked" : ""))
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .frame(minHeight: 44)
                .echoRow(vertical: Spacing.sm, fill: Palette.teal.opacity(0.10))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the exact text that was sent")

            if expanded {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Chosen because: \(plan.selectionReason).")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !plan.masking.isEmpty {
                        Label("\(plan.maskedCount) names replaced on this phone (\(plan.masking.entries.prefix(3).map { "\($0.original) → \($0.token)" }.joined(separator: ", "))\(plan.maskedCount > 3 ? "…" : "")). The mapping never leaves it.",
                              systemImage: "theatermasks")
                            .font(.caption)
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
                    Text("0 bytes of audio. Only the text above, plus your question.")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.teal)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoRow()
                .transition(.opacity)
            }
        }
        .onChange(of: expand) { _, open in withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { expanded = open } }
    }
}

/// Shown while a cloud call is in flight.
struct SendingCard: View {
    let plan: TierTwoPlan
    let isStub: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            RouteStrip(active: .cloud)
            HStack(spacing: Spacing.md) {
                ProgressView().tint(Palette.cloud)
                Text(isStub ? "Preparing a stub preview. Nothing is sent."
                            : "Sending \(plan.snippets.count) snippets (\(ByteFormat.short(plan.bodyBytes))) to Muse Spark…")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
            }
            Text("Chosen because: \(plan.selectionReason). No audio is sent.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Asking Muse Spark")
    }
}

/// A cloud call that failed. Says plainly what happened and what, if anything, left the phone.
struct CloudFailureCard: View {
    let failure: CloudFailure
    let player: ChunkPlayer
    let onRetry: () -> Void

    private var sentNothing: Bool { failure.error == .offline }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            RouteStrip(active: .cloud)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Muse couldn't answer", systemImage: "exclamationmark.triangle.fill")
                    .font(.echoLabel)
                    .foregroundStyle(Palette.amber)
                Text(failure.error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(sentNothing ? "Nothing left your phone."
                                 : "The request carried \(failure.plan.snippets.count) text snippets (\(ByteFormat.short(failure.plan.bodyBytes))), no audio. It is in your Privacy Ledger.")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            EchoButton(title: "Try again", systemImage: "arrow.clockwise", action: onRetry)

            if let local = failure.localAnswer {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader("Closest moments on this phone", style: .overline)
                    ForEach(local.sources) { SourceRow(hit: $0, terms: local.highlightTerms, player: player) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }
}
