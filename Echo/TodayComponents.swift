import SwiftUI

// MARK: - Funnel

/// recorded -> kept by the watch -> confirmed on the phone, with the share that never gets stored.
struct FunnelCard: View {
    let model: PipelineModel
    /// On the You page the numbers are the point, so they are always shown in full.
    var alwaysFull = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Once the day has settled the three bars are tucked away behind "Details"; while it syncs they show the progress.
    @State private var showDetail = false

    private var showsRows: Bool { !model.isSettled || showDetail || alwaysFull }

    /// Never smaller than what the watch kept, so the bars stay proportional even if the session totals are missing.
    private var recorded: Double { max(model.recordedSeconds, model.watchKeptSeconds, 0.0001) }

    /// Settled, and the person hasn't asked for the numbers: one sentence is enough.
    private var isSummarised: Bool { model.isSettled && model.recordedSeconds > 0 && !showDetail && !alwaysFull }

    var body: some View {
        if isSummarised { summary } else { full }
    }

    private var summary: some View {
        Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showDetail = true }
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(Palette.teal).accessibilityHidden(true)
                Text("Kept \(Format.clock(model.phoneConfirmedSeconds)) of \(Format.clock(recorded)). Echo skipped the silence.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Details")
                    .font(Font.echoMeta.weight(.semibold))
                    .foregroundStyle(Palette.textSecondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .echoCard(padding: Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityHint("Shows how much was heard, kept and saved")
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // On its own page the title is already above the card.
            if !alwaysFull {
                SectionHeader(title: "What Echo kept") {
                    if model.isSettled {
                        Label("Settled", systemImage: "checkmark.circle.fill")
                            .font(Font.echoMeta.weight(.medium))
                            .foregroundStyle(Palette.teal)
                    } else if model.isListening || model.pendingCount > 0 {
                        Label("Processing", systemImage: "waveform")
                            .font(Font.echoMeta.weight(.medium))
                            .foregroundStyle(Palette.blue)
                            .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
                    }
                }
            }

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

            if showsRows {
                Group {
                    FunnelRow(label: "Heard by the watch", seconds: recorded,
                              fraction: model.recordedSeconds > 0 || model.watchKeptSeconds > 0 ? 1 : 0, tint: Palette.textSecondary)
                    FunnelRow(label: "Kept as speech", seconds: model.watchKeptSeconds,
                              fraction: model.watchKeptSeconds / recorded, tint: Palette.blue)
                    FunnelRow(label: "Saved on this phone", seconds: model.phoneConfirmedSeconds,
                              fraction: model.phoneConfirmedSeconds / recorded, tint: Palette.teal)
                }
                .transition(.opacity)
            }
            if model.isSettled && model.recordedSeconds > 0 && !alwaysFull {
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { showDetail.toggle() }
                } label: {
                    Label(showDetail ? "Hide details" : "Details", systemImage: showDetail ? "chevron.up" : "chevron.down")
                        .font(Font.echoMeta.weight(.medium))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
