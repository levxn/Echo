import SwiftUI
import UIKit

/// Shown in the Ask tab while a spoken question is being taken: listening, understanding, or what went wrong.
struct VoiceCard: View {
    let voice: VoiceAskModel
    let onStop: () -> Void
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch voice.state {
        case .idle:
            EmptyView()
        case .listening:
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.lg) {
                    LevelMeter(level: voice.recorder.level, reduceMotion: reduceMotion)
                        .frame(width: 64, height: 40)
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Listening…")
                            .font(.echoLabel)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Say your question. I'll stop when you pause.")
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: Spacing.sm) {
                    EchoButton(title: "Tap to stop", systemImage: "stop.fill", style: .prominent, tint: Palette.teal, action: onStop)
                    EchoButton(title: "Cancel", style: .quiet) { voice.cancel() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard()
            .accessibilityElement(children: .contain)
            .transition(.echoRise(reduceMotion: reduceMotion))
        case .understanding:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.md) {
                    ProgressView().tint(Palette.teal)
                    Text("Understanding…")
                        .font(.echoLabel)
                        .foregroundStyle(Palette.textPrimary)
                }
                Text("Done on this phone. The recording is deleted, and no audio is ever sent.")
                    .font(.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard()
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        case .problem(let problem):
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Label("Couldn't take that question", systemImage: "mic.slash.fill")
                    .font(.echoLabel)
                    .foregroundStyle(Palette.amber)
                Text(problem.message)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Spacing.sm) {
                    if problem.needsSettings {
                        EchoButton(title: "Open Settings", systemImage: "gearshape.fill", style: .prominent, tint: Palette.teal) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    } else {
                        EchoButton(title: "Try again", systemImage: "mic.fill", style: .prominent, tint: Palette.teal, action: onRetry)
                    }
                    EchoButton(title: "Dismiss", style: .quiet) { voice.dismissProblem() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard()
            .accessibilityElement(children: .contain)
            .transition(.opacity)
        }
    }
}

/// Seven bars that follow the voice. Still, at a medium height, when Reduce Motion is on.
private struct LevelMeter: View {
    let level: Double
    let reduceMotion: Bool

    private static let shape: [Double] = [0.45, 0.7, 0.9, 1.0, 0.85, 0.65, 0.4]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.shape.indices, id: \.self) { i in
                Capsule()
                    .fill(Palette.teal)
                    .frame(width: 5, height: 8 + 32 * (reduceMotion ? 0.4 : level) * Self.shape[i])
            }
        }
        .frame(maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}
