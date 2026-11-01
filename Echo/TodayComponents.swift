import SwiftUI

// MARK: - Funnel

/// recorded -> kept by the watch -> confirmed on the phone, with the share that never gets stored.
struct FunnelCard: View {
    let model: PipelineModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Never smaller than what the watch kept, so the bars stay proportional even if the session totals are missing.
    private var recorded: Double { max(model.recordedSeconds, model.watchKeptSeconds, 0.0001) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            SectionHeader(title: "Today's funnel") {
                if model.isSettled {
                    Label("Settled", systemImage: "checkmark.circle.fill")
                        .font(Font.echoMeta.weight(.medium))
                        .foregroundStyle(Palette.teal)
                } else if model.session == .running || model.pendingCount > 0 {
                    Label("Processing", systemImage: "waveform")
                        .font(Font.echoMeta.weight(.medium))
                        .foregroundStyle(Palette.blue)
                        .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                }
            }

            FunnelRow(label: "Recorded on watch", seconds: recorded,
                      fraction: model.recordedSeconds > 0 || model.watchKeptSeconds > 0 ? 1 : 0, tint: Palette.textSecondary)
            FunnelRow(label: "Kept by watch", seconds: model.watchKeptSeconds,
                      fraction: model.watchKeptSeconds / recorded, tint: Palette.blue)
            FunnelRow(label: "Confirmed on phone", seconds: model.phoneConfirmedSeconds,
                      fraction: model.phoneConfirmedSeconds / recorded, tint: Palette.teal)

            if model.isSettled && model.recordedSeconds > 0 {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("\(Int((model.savedFraction * 100).rounded()))%")
                        .font(.echoScreenTitle)
                        .monospacedDigit()
                        .foregroundStyle(Palette.accentGradient)
                    Text("of the day was never stored")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .animation(reduceMotion ? nil : .smooth(duration: 0.5), value: model.isSettled)
        .accessibilityElement(children: .contain)
    }
}

private struct FunnelRow: View {
    let label: String
    let seconds: Double
    let fraction: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
                Text(Format.clock(seconds))
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.fillStrong)
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 8)
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.6), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Format.spoken(seconds))
    }
}

// MARK: - Stage strip

struct StageStrip: View {
    let model: PipelineModel

    var body: some View {
        HStack(spacing: Spacing.sm) {
            StageChip(symbol: "tray.and.arrow.down.fill", label: "Received", count: model.arrivedCount, tint: Palette.blue)
            StageChip(symbol: "waveform.badge.magnifyingglass", label: "Checked", count: model.checkedCount, tint: Palette.blue)
            StageChip(symbol: "text.bubble.fill", label: "Written", count: model.transcribedCount, tint: Palette.teal)
            StageChip(symbol: "checkmark.seal.fill", label: "Stored", count: model.storedCount, tint: Palette.teal)
            StageChip(symbol: "xmark.circle.fill", label: "Dropped", count: model.droppedCount, tint: Palette.rose)
        }
    }
}

private struct StageChip: View {
    let symbol: String
    let label: String
    let count: Int
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(tint)
                .frame(height: 20)
            Text("\(count)")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(Font.echoMicro.weight(.medium))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .animation(reduceMotion ? nil : .snappy, value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(count)")
    }
}

// MARK: - Live feed

struct ChunkRow: View {
    let chunk: ChunkRecord

    private var isDropped: Bool { chunk.status == .dropped }

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(chunk.wallLabel)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
                Text(String(format: "%.1fs", chunk.duration))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: Spacing.tight) {
                if let text = chunk.transcript, !text.isEmpty {
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isDropped {
                    Label(String(format: "Not speech (%.2f)", chunk.speechConfidence ?? 0), systemImage: "xmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(Palette.rose)
                } else {
                    Text(chunk.status == .failed ? "Could not process" : "Working on it…")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                StageDots(status: chunk.status)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoRow(fill: isDropped ? Color.white.opacity(0.03) : Palette.fill)
        .opacity(isDropped ? 0.8 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Four stages as dots: received, speech check, transcribed, stored. The next stage pulses while work is pending.
private struct StageDots: View {
    let status: ChunkStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reached: Int {
        switch status {
        case .received: 1
        case .vad: 2
        case .asr: 3
        case .stored: 4
        case .dropped: 2
        case .failed: 1
        }
    }

    private var inFlight: Bool { status == .received || status == .vad || status == .asr }

    var body: some View {
        HStack(spacing: Spacing.tight) {
            ForEach(0..<4, id: \.self) { i in
                let lit = i < reached
                Circle()
                    .fill(color(for: i, lit: lit))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if inFlight && i == reached {
                            if reduceMotion {
                                Circle().stroke(Palette.blue, lineWidth: 1.5)
                            } else {
                                Circle().stroke(Palette.blue, lineWidth: 1.5)
                                    .phaseAnimator([0.6, 1.0]) { c, p in c.opacity(p) } animation: { _ in .easeInOut(duration: 0.7) }
                            }
                        }
                    }
            }
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(status == .dropped ? Palette.rose : Palette.textSecondary)
                .contentTransition(.opacity)
        }
    }

    private func color(for i: Int, lit: Bool) -> Color {
        if status == .dropped { return i < 2 ? Palette.rose : Color.white.opacity(0.12) }
        return lit ? (status == .stored ? Palette.teal : Palette.blue) : Color.white.opacity(0.12)
    }

    private var label: String {
        switch status {
        case .received: "Received"
        case .vad: "Speech confirmed"
        case .asr: "Transcribed"
        case .stored: "Stored"
        case .dropped: "Dropped"
        case .failed: "Failed"
        }
    }
}
