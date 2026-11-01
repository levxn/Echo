import SwiftUI

/// The watch is a silent sensor, so this is a "proof of life" screen: a ring that breathes with the
/// microphone level and traces replay progress, three counters, and one control.
struct ContentView: View {
    let engine: CaptureEngine
    let link: WatchLink

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        switch engine.phase {
        case .idle: "Ready"
        case .running: "Listening"
        case .paused: "Paused"
        case .finished: "Day captured"
        }
    }

    private var ringTint: Color {
        switch engine.phase {
        case .paused: Palette.textTertiary
        case .idle: Palette.blue
        default: engine.speaking ? Palette.teal : Palette.blue
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground(calm: true, fps: 12)
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Left-aligned so it never collides with the system clock at the top right.
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(title)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(link.reachable ? Palette.teal : Palette.rose)
                            .frame(width: 6, height: 6)
                        Text(link.reachable ? "Phone linked" : "No phone nearby")
                            .font(.caption2)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                HStack(spacing: Spacing.sm) {
                    MicRing(progress: engine.progress, level: engine.level, tint: ringTint,
                            active: engine.phase == .running, reduceMotion: reduceMotion)
                        .frame(width: 80, height: 80)

                    VStack(alignment: .leading, spacing: 2) {
                        Counter(value: engine.captured, label: "heard")
                        Counter(value: link.queued, label: "queue")
                        Counter(value: link.synced, label: "synced")
                    }
                }

                Button(action: primaryAction) {
                    Label(buttonTitle, systemImage: buttonSymbol)
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel(buttonLabel)

            }
            .padding(.horizontal, Spacing.sm)
        }
    }

    private var buttonTitle: String {
        switch engine.phase {
        case .running: "Pause"
        case .paused: "Resume"
        case .idle: "Start day"
        case .finished: "Replay"
        }
    }

    private var buttonSymbol: String {
        switch engine.phase {
        case .running: "pause.fill"
        case .paused: "play.fill"
        case .idle: "play.fill"
        case .finished: "arrow.counterclockwise"
        }
    }

    private var buttonLabel: String {
        switch engine.phase {
        case .running: "Pause listening"
        case .paused: "Resume listening"
        case .idle: "Start the day"
        case .finished: "Replay the day"
        }
    }

    private func primaryAction() {
        switch engine.phase {
        case .idle, .finished: engine.start()
        case .running, .paused: engine.togglePause()
        }
    }
}

private struct MicRing: View {
    let progress: Double
    let level: Double
    let tint: Color
    let active: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            // Breathing glow driven by the live level.
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0)], center: .center,
                                     startRadius: 4, endRadius: 52))
                .scaleEffect(active && !reduceMotion ? 0.8 + level * 0.45 : 0.85)
                .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0.3), value: level)
            Circle().stroke(Palette.stroke, lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.002, progress))
                .stroke(Palette.accentGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 0.1), value: progress)
            Image(systemName: "waveform")
                .font(.title2.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
                .symbolEffect(.variableColor.iterative, isActive: active && !reduceMotion)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone")
        .accessibilityValue("\(Int(progress * 100)) percent of the day captured")
    }
}

private struct Counter: View {
    let value: Int
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text("\(value)")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: value)
                .frame(minWidth: 26, alignment: .trailing)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.tight)
        .padding(.vertical, Spacing.xs)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
