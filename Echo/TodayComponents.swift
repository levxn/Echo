import SwiftUI

// MARK: - Funnel

/// recorded -> kept by the watch -> confirmed on the phone, with the share that never gets stored.
struct FunnelCard: View {
    let model: PipelineModel

    /// Never smaller than what the watch kept, so the bars stay proportional even if the session totals are missing.
    private var recorded: Double { max(model.recordedSeconds, model.watchKeptSeconds, 0.0001) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today's funnel")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if model.isSettled {
                    Label("Settled", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.teal)
                } else if model.session == .running || model.pendingCount > 0 {
                    Label("Processing", systemImage: "waveform")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Palette.blue)
                        .symbolEffect(.variableColor.iterative)
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
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.accentGradient)
                    Text("of the day was never stored")
                        .font(.subheadline)
                        .foregroundStyle(Palette.textSecondary)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .animation(.smooth(duration: 0.5), value: model.isSettled)
        .accessibilityElement(children: .contain)
    }
}

private struct FunnelRow: View {
    let label: String
    let seconds: Double
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(6, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 8)
        }
        .animation(.smooth(duration: 0.6), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Format.clock(seconds)) minutes")
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

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(height: 20)
            Text("\(count)")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.snappy, value: count)
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
            VStack(alignment: .leading, spacing: 2) {
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

            VStack(alignment: .leading, spacing: 6) {
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
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(isDropped ? 0.03 : 0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(isDropped ? 0.8 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// Four stages as dots: received, speech check, transcribed, stored. The next stage pulses while work is pending.
private struct StageDots: View {
    let status: ChunkStatus

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
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                let lit = i < reached
                Circle()
                    .fill(color(for: i, lit: lit))
                    .frame(width: 8, height: 8)
                    .overlay {
                        if inFlight && i == reached {
                            Circle().stroke(Palette.blue, lineWidth: 1.5)
                                .phaseAnimator([0.6, 1.0]) { c, p in c.opacity(p) } animation: { _ in .easeInOut(duration: 0.7) }
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
