import SwiftUI

/// Says where an answer came from in one line. Tap it to see both places a question can be answered (this phone, or Muse in
/// the cloud), so the routing story stays one tap away without taking space above every answer.
struct RouteStrip: View {
    enum Active { case local, cloud, none }
    let active: Active
    @State private var open = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var summary: (symbol: String, text: String, tint: Color) {
        switch active {
        case .local: ("iphone", "On this phone", Palette.local)
        case .cloud: ("cloud.fill", "Muse Spark", Palette.cloud)
        case .none: ("hand.raised.fill", "Not sent to the cloud", Palette.amber)
        }
    }

    /// With very large text only the one that answered is shown (both when none did), so the answer stays on screen.
    private func showsPill(_ tier: Active?) -> Bool {
        guard typeSize.isAccessibilitySize, active != .none else { return true }
        return tier == active
    }

    /// Two pills side by side do not fit once text is very large, so they stack.
    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: Spacing.sm)) : AnyLayout(HStackLayout(spacing: Spacing.sm))
    }

    var body: some View {
        let s = summary
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { open.toggle() }
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: s.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(s.tint)
                        .accessibilityHidden(true)
                    Text(s.text)
                        .font(.echoLabel)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .echoRow(vertical: 0, fill: s.tint.opacity(0.12))
                .contentShape(Rectangle())
            }
            .buttonStyle(EchoPressStyle())
            .accessibilityLabel(s.text)
            .accessibilityValue(open ? "expanded" : "collapsed")
            .accessibilityHint(open ? "Hides the details" : "Shows how the question was routed")

            if open {
                layout {
                    if showsPill(.local) {
                        TierPill(symbol: "iphone", title: "This phone", detail: "On-device", tint: Palette.local,
                                 state: active == .local ? .active : .idle)
                    }
                    if showsPill(.cloud) {
                        TierPill(symbol: "cloud.fill", title: "Muse Spark", detail: "Meta API", tint: Palette.cloud,
                                 state: active == .cloud ? .active : .idle)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}

private struct TierPill: View {
    enum PillState { case active, idle }

    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let state: PillState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(state == .active ? tint : Palette.textTertiary)
            Text(title)
                .font(Font.echoMicro.weight(.semibold))
                .foregroundStyle(state == .active ? Palette.textPrimary : Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.system(.caption2))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(state == .active ? tint.opacity(0.18) : Palette.fill)
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .strokeBorder(state == .active ? tint.opacity(0.8) : Palette.stroke,
                              style: StrokeStyle(lineWidth: 1))
        }
        // Dimmed by dashing and colour, not by opacity: fading the whole pill would push its text below contrast.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: state == .active)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(state == .active ? "used for this answer" : "not used")
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
                        .font(.echoLabel)
                        .foregroundStyle(Palette.amber)
                    Text("This question needs synthesis, but you've switched the cloud off, so nothing was sent. Here are the closest moments on this phone. Turn the cloud back on in the Privacy Ledger to let Muse answer.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                case .declined:
                    Label("Not sent", systemImage: "hand.raised.fill")
                        .font(.echoLabel)
                        .foregroundStyle(Palette.amber)
                    Text("You chose not to send this to Muse, so nothing left your phone. Here are the closest moments on this phone.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                case .nothingMatched:
                    Label("Nothing matched", systemImage: "magnifyingglass")
                        .font(.echoLabel)
                        .foregroundStyle(Palette.amber)
                    Text("Nothing in today's transcripts matches that closely enough, so nothing was sent anywhere.")
                        .font(.subheadline).foregroundStyle(Palette.textSecondary)
                case nil:
                    Label("Answered on this phone", systemImage: "lock.fill")
                        .font(.echoLabel)
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
            SectionHeader("Closest moments", style: .overline)
            ForEach(answer.sources) { SourceRow(hit: $0, terms: answer.highlightTerms, player: player) }
        }
    }

    @ViewBuilder
    private func localAnswer(_ answer: Answer) -> some View {
        Text(Highlighter.attributed(answer.headline, terms: answer.highlightTerms, highlight: Palette.teal, base: Palette.textPrimary))
            .font(.echoAnswer)
            .fixedSize(horizontal: false, vertical: true)

        if !answer.headlineChunk.isOn(DayID.today()) {
            Label("From \(DayID.longLabel(answer.headlineChunk.dayId).lowercased())", systemImage: "calendar")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
        }

        AnswerActions(speak: answer.headline,
                      share: ShareText.answer(question: result.query, answer: answer.headline,
                                              lines: answer.sources.prefix(3).map { "• At \($0.chunk.stamp()): “\($0.chunk.transcript ?? "")”" }))

        if !result.outcome.unknownTerms.isEmpty {
            Label("Never heard “\(result.outcome.unknownTerms.joined(separator: ", "))” today, so matched on the rest.",
                  systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
        }

        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("From these moments", style: .overline)
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
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(hit.chunk.stamp())
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(String(format: "%.0fs", hit.chunk.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(minWidth: 48, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)

            Text(Highlighter.attributed(hit.chunk.transcript ?? "", terms: terms, highlight: Palette.teal, base: Palette.textSecondary))
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            PlayButton(isPlaying: playing, label: "Play the audio from \(hit.chunk.stamp())") { player.toggle(hit.chunk) }
        }
        .echoRow(vertical: Spacing.sm)
    }
}
