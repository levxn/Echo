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
    private let link: WatchLink
    private var generation = 0

    init(link: WatchLink) { self.link = link }

    func ask(_ preset: QuickAsk) async {
        generation += 1
        let mine = generation
        state = .asking(preset)
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
        .animation(.smooth(duration: 0.25), value: ask.state)
    }

    // MARK: Idle

    private var presets: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ask your day")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(link.reachable ? "Answered by your phone" : "No phone nearby")
                        .font(.system(size: 10))
                        .foregroundStyle(link.reachable ? Palette.textSecondary : Palette.rose)
                }
                ForEach(QuickAsk.presets) { preset in
                    Button { Task { await ask.ask(preset) } } label: {
                        HStack(spacing: 6) {
                            Image(systemName: preset.symbol)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(preset.usesCloud ? Palette.cloud : Palette.local)
                                .frame(width: 18)
                            Text(preset.label)
                                .font(.system(.footnote, design: .rounded, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: preset.usesCloud ? "cloud.fill" : "lock.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .padding(.horizontal, Spacing.md)
                        .frame(maxWidth: .infinity, minHeight: 40)
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
            Text(preset.usesCloud ? "Asking Muse through your phone…" : "Asking your phone…")
                .font(.system(size: 10))
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
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(2)
                Button { ask.reset() } label: {
                    Label("Ask another", systemImage: "arrow.uturn.backward")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
            }
            .padding(.horizontal, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }

    private func failed(_ preset: QuickAsk) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "iphone.slash")
                .font(.system(size: 22))
                .foregroundStyle(Palette.amber)
            Text("No answer")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Is your phone nearby, with Echo open?")
                .font(.system(size: 11))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
            HStack(spacing: Spacing.sm) {
                Button("Retry") { Task { await ask.ask(preset) } }
                Button("Back") { ask.reset() }
            }
            .font(.system(.footnote, design: .rounded, weight: .semibold))
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
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.18), in: Capsule())
    }
}
