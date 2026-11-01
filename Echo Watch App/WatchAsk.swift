import Observation
import SwiftUI
import WatchKit

/// Quick-ask: tap a preset on the watch, the phone answers (on its own, or with Muse for broad questions), and a
/// short answer comes back. The watch never sees transcripts or audio, only the answer.
@MainActor
@Observable
final class WatchAsk {
    enum State: Equatable {
        case idle
        case asking(QuickAsk)
        case answered(QuickAsk, WatchAnswer)
        case failed(QuickAsk)
    }

    /// 0 = capture, 1 = Ask. Lives here so the phone (demo driver) can bring the Ask page forward.
    var page = 0
    private(set) var state: State = .idle
    /// True once an answer has taken more than a few seconds (the phone may be waiting for the user to approve).
    private(set) var waitingLong = false
    private let link: WatchLink
    private var generation = 0

    init(link: WatchLink) { self.link = link }

    func ask(_ preset: QuickAsk) async {
        generation += 1
        let mine = generation
        state = .asking(preset)
        waitingLong = false
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, mine == self.generation, case .asking = self.state else { return }
            self.waitingLong = true
        }
        let answer = await link.ask(preset.question)
        guard mine == generation else { return }
        if let answer {
            state = .answered(preset, answer)
            WKInterfaceDevice.current().play(answer.source == .none ? .failure : .success)
        } else {
            state = .failed(preset)
            WKInterfaceDevice.current().play(.failure)
        }
    }

    /// Runs preset `index` as if tapped.
    func run(preset index: Int) {
        guard QuickAsk.presets.indices.contains(index) else { return }
        page = 1
        Task { await ask(QuickAsk.presets[index]) }
    }

    func reset() {
        generation += 1
        state = .idle
    }
}

struct AskWatchView: View {
    let ask: WatchAsk
    let link: WatchLink
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AuroraBackground(calm: true, fps: 12)
            switch ask.state {
            case .idle: presets
            case .asking(let preset): asking(preset)
            case .answered(let preset, let answer): answered(preset, answer)
            case .failed(let preset): failed(preset)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: ask.state)
    }

    // MARK: Idle

    private var presets: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Ask your day")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(link.reachable ? "Answered by your phone" : "No phone nearby")
                        .font(.caption2)
                        .foregroundStyle(link.reachable ? Palette.textSecondary : Palette.rose)
                }
                ForEach(QuickAsk.presets) { preset in
                    Button { Task { await ask.ask(preset) } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.symbol)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(preset.usesCloud ? Palette.cloud : Palette.local)
                                .frame(width: 18)
                            Text(preset.label)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: preset.usesCloud ? "cloud.fill" : "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        .padding(.horizontal, Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(EchoPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .disabled(!link.reachable)
                    .accessibilityHint(preset.usesCloud ? "Uses Muse on your phone's connection" : "Answered on your phone")
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Asking, answered, failed

    private func asking(_ preset: QuickAsk) -> some View {
        VStack(spacing: Spacing.sm) {
            ProgressView().tint(preset.usesCloud ? Palette.cloud : Palette.local)
            Text(preset.question)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(ask.waitingLong ? "Waiting for your phone. It may need you to approve the request."
                                 : (preset.usesCloud ? "Asking Muse through your phone…" : "Asking your phone…"))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private func answered(_ preset: QuickAsk, _ answer: WatchAnswer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                badge(answer)
                Text(answer.text)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(String(format: "%.1f s · %@", Double(answer.milliseconds) / 1000, preset.question))
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                WatchButton(title: "Ask another", systemImage: "arrow.uturn.backward") { ask.reset() }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }

    private func failed(_ preset: QuickAsk) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "iphone.slash")
                .font(.title3)
                .foregroundStyle(Palette.amber)
            Text("No answer")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Is your phone nearby, with Echo open?")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
            WatchButton(title: "Retry", systemImage: "arrow.clockwise") { Task { await ask.ask(preset) } }
            WatchButton(title: "Back", systemImage: nil, quiet: true) { ask.reset() }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func badge(_ answer: WatchAnswer) -> some View {
        let (text, symbol, tint): (String, String, Color) = switch answer.source {
        case .local: ("On your phone", "lock.fill", Palette.local)
        case .muse: ("Muse Spark", "cloud.fill", Palette.cloud)
        case .stub: ("Stub · nothing sent", "testtube.2", Palette.amber)
        case .none: ("No answer", "info.circle", Palette.amber)
        }
        return Label(text, systemImage: symbol)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
    }
}

/// A 44pt glass capsule button for the watch.
private struct WatchButton: View {
    let title: String
    let systemImage: String?
    var quiet = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
            .foregroundStyle(quiet ? Palette.textSecondary : Palette.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(EchoPressStyle())
        .modifier(WatchGlass(quiet: quiet))
    }

    private struct WatchGlass: ViewModifier {
        let quiet: Bool
        func body(content: Content) -> some View {
            if quiet { content } else { content.glassEffect(.regular.interactive(), in: .capsule) }
        }
    }
}
