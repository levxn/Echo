import SwiftUI

enum ByteFormat {
    static func short(_ n: Int) -> String { n < 1024 ? "\(n) B" : String(format: "%.1f KB", Double(n) / 1024) }
}

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
                HStack(spacing: 6) {
                    Image(systemName: isStub ? "testtube.2" : "cloud.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isStub ? "Stub preview · no API key" : "Answered by Muse Spark")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(isStub ? Palette.amber : Palette.cloud)
                Text(result.decision.reason)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(result.answer.answer)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !result.answer.items.isEmpty {
                VStack(spacing: Spacing.sm) {
                    ForEach(result.answer.items) { ItemRow(item: $0, chunk: chunkFor($0), player: player) }
                }
            }

            SentDisclosure(plan: result.plan, isStub: isStub, expand: expandSent).id("sentPanel")

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
                Label(label, systemImage: playing ? "stop.fill" : "play.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 32)
                    .background(tint.opacity(0.16), in: Capsule())
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
        .padding(Spacing.md)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { if chunk != nil { withAnimation(.smooth(duration: 0.25)) { showQuote.toggle() } } }
        .accessibilityElement(children: .contain)
    }

    private var content: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                if !item.when.isEmpty {
                    Label(item.when, systemImage: "clock")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.cloud)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Palette.cloud.opacity(0.16), in: Capsule())
                }
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(.smooth(duration: 0.25)) { expanded.toggle() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: isStub ? "eye" : "paperplane")
                        .font(.system(size: 13, weight: .semibold))
                    Text(isStub ? "What would be sent" : "What left your phone")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text("\(plan.snippets.count) snippets · \(ByteFormat.short(plan.bodyBytes)) · no audio")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 44)
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
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .transition(.opacity)
            }
        }
        .onChange(of: expand) { _, open in withAnimation(.smooth(duration: 0.25)) { expanded = open } }
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
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
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

            Button(action: onRetry) {
                Label("Try again", systemImage: "arrow.clockwise")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(EchoPressStyle())
            .glassEffect(.regular.interactive(), in: .capsule)

            if let local = failure.localAnswer {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Closest moments on this phone")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .textCase(.uppercase)
                    ForEach(local.sources) { SourceRow(hit: $0, terms: local.highlightTerms, player: player) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }
}
