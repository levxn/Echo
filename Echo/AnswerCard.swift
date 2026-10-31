import SwiftUI

/// Shows where a question was answered: this phone, the (design-only) on-device Glimmer tier, or Muse in the cloud.
struct RouteStrip: View {
    enum Active { case local, cloud, none }
    let active: Active

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

    private var held: Bool { result.note != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            RouteStrip(active: held ? .none : .local)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                switch result.note {
                case .cloudOff:
                    Label("Cloud is off", systemImage: "cloud.slash.fill")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                    Text("This question needs synthesis, but you've switched the cloud off, so nothing was sent. Here are the closest moments on this phone. Turn the cloud back on in the Privacy Ledger to let Muse answer.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                case .nothingMatched:
                    Label("Nothing matched", systemImage: "magnifyingglass")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                    Text("Nothing in today's transcripts matches that closely enough, so nothing was sent anywhere.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                case nil:
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                        Text("Answered on this phone")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                    }
                    .foregroundStyle(Palette.local)
                    Text(result.decision.reason)
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            if let answer = result.answer {
                if held { sources(answer) } else { localAnswer(answer) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    private func sources(_ answer: Answer) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Closest moments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.textSecondary)
                .textCase(.uppercase)
            ForEach(answer.sources) { SourceRow(hit: $0, terms: answer.highlightTerms, player: player) }
        }
    }

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
}

struct SourceRow: View {
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
