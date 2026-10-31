import SwiftUI

/// Shows where a question was answered: this phone, the (design-only) on-device Glimmer tier, or Muse in the cloud.
struct RouteStrip: View {
    let active: Tier

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TierPill(symbol: "iphone", title: "This phone", detail: "Tier 0", tint: Palette.local,
                     state: active == .local ? .active : .idle)
            TierPill(symbol: "cpu", title: "Muse Glimmer", detail: "Tier 1 · design only", tint: Palette.textTertiary,
                     state: .designOnly)
            TierPill(symbol: "cloud.fill", title: "Muse Spark", detail: "Tier 2 · Meta API", tint: Palette.cloud,
                     state: active == .cloud ? .active : .idle)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct TierPill: View {
    enum PillState { case active, idle, designOnly }

    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let state: PillState

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(state == .active ? tint : Palette.textTertiary)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state == .active ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(state == .active ? tint.opacity(0.18) : Color.white.opacity(0.04))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(state == .active ? tint.opacity(0.8) : Color.white.opacity(0.1),
                              style: StrokeStyle(lineWidth: 1, dash: state == .designOnly ? [4, 3] : []))
        }
        .opacity(state == .designOnly ? 0.75 : 1)
        .animation(.easeOut(duration: 0.25), value: state == .active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(state == .active ? "used for this answer" : (state == .designOnly ? "not available in this demo" : "not used"))
    }
}

struct AnswerCard: View {
    let result: AskResult
    let player: ChunkPlayer

    private var isLocal: Bool { result.decision.tier == .local }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            RouteStrip(active: result.decision.tier)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: 6) {
                    Image(systemName: isLocal ? "lock.fill" : "cloud.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(isLocal ? "Answered on this phone" : "Needs Muse Spark")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
                .foregroundStyle(isLocal ? Palette.local : Palette.cloud)
                Text(result.decision.reason)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLocal, let answer = result.answer {
                localAnswer(answer)
            } else {
                escalation
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    // MARK: Tier 0

    @ViewBuilder
    private func localAnswer(_ answer: Answer) -> some View {
        Text(Highlighter.attributed(answer.headline, terms: answer.highlightTerms, highlight: Palette.teal, base: Palette.textPrimary))
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)

        if !result.outcome.unknownTerms.isEmpty {
            Label("Never heard “\(result.outcome.unknownTerms.joined(separator: ", "))” today, so matched on the rest.",
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }

        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("From these moments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .textCase(.uppercase)
            ForEach(answer.sources) { hit in
                SourceRow(hit: hit, terms: answer.highlightTerms, player: player)
            }
        }

        Text("Searched \(result.outcome.corpusSize) moments in \(String(format: "%.0f", result.outcome.elapsedMs)) ms · nothing left this phone")
            .font(.caption)
            .foregroundStyle(Palette.textSecondary)
    }

    // MARK: Tier 2

    private var escalation: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Echo would send only text snippets, never audio:")
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)
            ForEach(result.outcome.hits.prefix(3)) { hit in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Text(hit.chunk.wallLabel)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Palette.cloud)
                        .frame(width: 44, alignment: .leading)
                    Text(hit.chunk.transcript ?? "")
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
            }
            Text("The cloud step connects to the Meta Model API next.")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.cloud.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SourceRow: View {
    let hit: Hit
    let terms: [String]
    let player: ChunkPlayer

    private var playing: Bool { player.playingID == hit.chunk.id }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.chunk.wallLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(String(format: "%.0fs", hit.chunk.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(width: 48, alignment: .leading)

            Text(Highlighter.attributed(hit.chunk.transcript ?? "", terms: terms, highlight: Palette.teal, base: Palette.textSecondary))
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { player.toggle(hit.chunk) } label: {
                Image(systemName: playing ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(EchoPressStyle())
            .accessibilityLabel(playing ? "Stop audio" : "Play the audio from \(hit.chunk.wallLabel)")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
