import Observation
import SwiftUI
import WatchKit

/// Asking from the watch: tap the mic and speak, tap a suggestion, or reopen something asked earlier. The phone does
/// the work (on its own, or with Muse for broad questions) and the watch only sees the short answer. Spoken questions
/// are understood on the phone too, so the audio never goes further than that.
@MainActor
@Observable
final class WatchAsk {
    /// A question on its way, with what the screen needs to say about it.
    struct Asked: Equatable {
        var question: String
        var usesCloud: Bool
        var via: AskVia
        /// Set when this was opened from Recent: when it was first asked.
        var when: Date?

        init(question: String, usesCloud: Bool = false, via: AskVia, when: Date? = nil) {
            self.question = question; self.usesCloud = usesCloud; self.via = via; self.when = when
        }
    }

    enum State: Equatable {
        case idle
        case listening
        case understanding
        case asking(Asked)
        case answered(Asked, WatchAnswer)
        /// The phone didn't answer.
        case failed(Asked)
        /// The question couldn't be captured or understood; says why.
        case problem(String)
    }

    /// 0 = capture, 1 = Ask. Lives here so the phone (demo driver) can bring the Ask page forward.
    var page = 0
    private(set) var state: State = .idle
    /// True once an answer has taken more than a few seconds (the phone may be waiting for the user to approve).
    private(set) var waitingLong = false
    /// The last few questions, newest first. The phone's list wins whenever it can be reached.
    private(set) var recent: [HistoryItem]
    let recorder = QuestionRecorder()
    let speaker = Speaker()
    private let link: WatchLink
    private let cache: HistoryCache
    private var generation = 0
    private var voiceCount = 0

    init(link: WatchLink, cache: HistoryCache = HistoryCache()) {
        self.link = link
        self.cache = cache
        recent = cache.items
    }

    // MARK: Asking

    func ask(_ preset: QuickAsk) async {
        await ask(Asked(question: preset.question, usesCloud: preset.usesCloud, via: .watch))
    }

    func ask(_ asked: Asked) async {
        generation += 1
        await run(asked, generation)
    }

    /// Runs preset `index` as if tapped.
    func run(preset index: Int) {
        guard QuickAsk.presets.indices.contains(index) else { return }
        page = 1
        Task { await ask(QuickAsk.presets[index]) }
    }

    /// Runs recorded question `clip` (1...5) as if spoken, for the demo and the hooks.
    func run(voice clip: Int) {
        page = 1
        Task { await listen(clip: clip) }
    }

    /// Shows an earlier answer straight away, with no new request.
    func open(_ item: HistoryItem) {
        generation += 1
        speaker.stop()
        let asked = Asked(question: item.question, usesCloud: item.source == .muse || item.source == .stub, via: item.via, when: item.timestamp)
        state = .answered(asked, WatchAnswer(text: item.answer, source: item.source))
    }

    func reset() {
        generation += 1
        recorder.stop()
        speaker.stop()
        state = .idle
    }

    private func run(_ asked: Asked, _ mine: Int) async {
        state = .asking(asked)
        waitingLong = false
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, mine == self.generation, case .asking = self.state else { return }
            self.waitingLong = true
        }
        speaker.stop()
        let answer = await link.ask(asked.question, via: asked.via)
        guard mine == generation else { return }
        if let answer {
            state = .answered(asked, answer)
            // The phone says whether answers to spoken questions should be read aloud (a setting there).
            if answer.speak { speaker.speak(answer.text) }
            WKInterfaceDevice.current().play(answer.source == .none ? .failure : .success)
            AccessibilityNotification.Announcement("Answer: \(answer.text)").post()
            // Show it in Recent now; the phone's own list replaces this a moment later.
            cache.insert(HistoryItem(question: asked.question, answer: answer.text, source: answer.source, via: asked.via))
            recent = cache.items
            await refreshRecent()
        } else {
            state = .failed(asked)
            WKInterfaceDevice.current().play(.failure)
        }
    }

    // MARK: Voice

    /// Tap the mic: listen for a question, have the phone understand it, then ask it. Tapping again while listening
    /// ends the recording early. `clip` picks which recorded question stands in for the microphone in a simulator.
    func listen(clip: Int? = nil) async {
        if case .listening = state { recorder.stop(); return }
        switch state {
        case .idle, .problem, .failed, .answered: break
        default: return
        }
        generation += 1
        let mine = generation
        // A recording that was just cancelled may still be winding down.
        for _ in 0..<20 where recorder.phase != .idle { try? await Task.sleep(for: .milliseconds(50)) }
        state = .listening
        WKInterfaceDevice.current().play(.start)
        AccessibilityNotification.Announcement("Listening. Ask your question.").post()
        let index = clip.map { $0 - 1 } ?? voiceCount
        voiceCount += 1
        let result = await recorder.record(QuestionRecorder.defaultSource(next: index))
        guard mine == generation else { return }
        switch result {
        case .failure(let error):
            problem(error.message)
        case .success(let clip):
            state = .understanding
            WKInterfaceDevice.current().play(.stop)
            let reply = await link.transcribe(clip)
            guard mine == generation else { return }
            switch reply {
            case .heard(let text):
                WKInterfaceDevice.current().play(.click)
                AccessibilityNotification.Announcement("Heard: \(text)").post()
                await run(Asked(question: text, via: .watchVoice), mine)
            default:
                problem(reply.message ?? "I couldn't understand that.")
            }
        }
    }

    private func problem(_ message: String) {
        state = .problem(message)
        WKInterfaceDevice.current().play(.failure)
        AccessibilityNotification.Announcement(message).post()
    }

    // MARK: Recent

    /// Fetches the phone's list (empty after the day is forgotten) and keeps a copy for when it is away.
    func refreshRecent() async {
        guard let items = await link.history() else { return }
        cache.replace(with: items)
        recent = cache.items
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
            case .idle: home
            case .listening: listening
            case .understanding: understanding
            case .asking(let asked): asking(asked)
            case .answered(let asked, let answer): answered(asked, answer)
            case .failed(let asked): failed(asked)
            case .problem(let message): problem(message)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: ask.state)
        .task { await ask.refreshRecent() }
        .onChange(of: link.reachable) { _, reachable in if reachable { Task { await ask.refreshRecent() } } }
    }

    // MARK: Home: the mic, suggestions, recent

    private var home: some View {
        ScrollViewReader { proxy in
            homeContent
                .task {
                    // Dev hook: `-ask-focus recent` (or `suggestions`) scrolls there, for screenshots.
                    let args = ProcessInfo.processInfo.arguments
                    guard let i = args.firstIndex(of: "-ask-focus"), i + 1 < args.count else { return }
                    try? await Task.sleep(for: .milliseconds(600))
                    proxy.scrollTo(args[i + 1], anchor: .top)
                }
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Ask")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Text(link.reachable ? "Answered by your phone" : "No phone nearby")
                        .font(.caption2)
                        .foregroundStyle(link.reachable ? Palette.textSecondary : Palette.rose)
                }

                micButton

                SectionLabel("Suggestions").id("suggestions")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.xs), GridItem(.flexible(), spacing: Spacing.xs)], spacing: Spacing.xs) {
                    ForEach(QuickAsk.presets) { preset in
                        Button { Task { await ask.ask(preset) } } label: {
                            VStack(spacing: Spacing.xxs) {
                                Image(systemName: preset.symbol)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(preset.usesCloud ? Palette.cloud : Palette.local)
                                Text(preset.label)
                                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Palette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .padding(.horizontal, Spacing.xs)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        }
                        .buttonStyle(EchoPressStyle())
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        .disabled(!link.reachable)
                        .accessibilityLabel(preset.question)
                        .accessibilityHint(preset.usesCloud ? "Uses Muse on your phone's connection" : "Answered on your phone")
                    }
                }

                if !ask.recent.isEmpty {
                    SectionLabel("Recent").id("recent")
                    ForEach(ask.recent) { item in
                        Button { ask.open(item) } label: { RecentRow(item: item) }
                            .buttonStyle(EchoPressStyle())
                            .accessibilityLabel(RecentRow.spoken(item))
                            .accessibilityHint("Shows the answer")
                    }
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }

    /// The one big control: tap it, say the question.
    private var micButton: some View {
        VStack(spacing: Spacing.xs) {
            Button { Task { await ask.listen() } } label: {
                Image(systemName: "mic.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 72, height: 72)
                    .contentShape(Circle())
            }
            .buttonStyle(EchoPressStyle())
            .glassEffect(.regular.tint(Palette.teal.opacity(0.45)).interactive(), in: .circle)
            .disabled(!link.reachable)
            .accessibilityLabel("Ask by voice")
            .accessibilityHint(link.reachable ? "Tap, then say your question" : "Your phone isn't nearby")
            .accessibilityAddTraits(.startsMediaSession)
            Text(link.reachable ? "Tap to ask" : "Phone needed to ask")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(link.reachable ? Palette.textPrimary : Palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: Listening, understanding

    private var listening: some View {
        VStack(spacing: Spacing.sm) {
            Button { Task { await ask.listen() } } label: {
                ListeningRing(level: ask.recorder.level, reduceMotion: reduceMotion)
                    .frame(width: 84, height: 84)
                    .contentShape(Circle())
            }
            .buttonStyle(EchoPressStyle())
            .accessibilityLabel("Listening")
            .accessibilityHint("Tap to stop")
            Text("Listening…")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Tap to stop")
                .font(.caption2)
                .foregroundStyle(Palette.textSecondary)
            WatchButton(title: "Cancel", systemImage: nil, quiet: true) { ask.reset() }
        }
        .padding(.horizontal, Spacing.md)
    }

    private var understanding: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView().tint(Palette.teal)
            Text("Understanding…")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Done on your phone. The recording is deleted.")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .accessibilityElement(children: .combine)
    }

    // MARK: Asking, answered, failed, problem

    private func asking(_ asked: WatchAsk.Asked) -> some View {
        VStack(spacing: Spacing.sm) {
            ProgressView().tint(asked.usesCloud ? Palette.cloud : Palette.local)
            VStack(spacing: Spacing.xxs) {
                if asked.via.isVoice {
                    Text("Heard")
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(asked.via.isVoice ? "“\(asked.question)”" : asked.question)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
            }
            Text(ask.waitingLong ? "Waiting for your phone. It may need you to approve the request."
                                 : (asked.usesCloud ? "Asking Muse through your phone…" : "Asking your phone…"))
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(.horizontal, Spacing.md)
        .accessibilityElement(children: .combine)
    }

    private func answered(_ asked: WatchAsk.Asked, _ answer: WatchAnswer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                badge(answer)
                Label {
                    Text(asked.question)
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(3)
                } icon: {
                    Image(systemName: asked.via.isVoice ? "mic.fill" : "text.bubble")
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                }
                Text(answer.text)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(footer(asked, answer))
                    .font(.caption2)
                    .foregroundStyle(Palette.textSecondary)
                if answer.source != .none {
                    WatchButton(title: ask.speaker.isSpeaking("answer") ? "Stop" : "Read aloud",
                                systemImage: ask.speaker.isSpeaking("answer") ? "stop.fill" : "speaker.wave.2.fill", quiet: true) {
                        ask.speaker.toggle(answer.text)
                    }
                }
                if asked.when == nil {
                    WatchButton(title: "Ask another", systemImage: "mic.fill") { ask.reset() }
                    WatchButton(title: "Ask again", systemImage: "arrow.clockwise", quiet: true) { Task { await ask.ask(asked) } }
                } else {
                    WatchButton(title: "Ask again", systemImage: "arrow.clockwise") {
                        Task { await ask.ask(WatchAsk.Asked(question: asked.question, usesCloud: asked.usesCloud, via: .watch)) }
                    }
                    WatchButton(title: "Back", systemImage: "chevron.backward", quiet: true) { ask.reset() }
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .scrollIndicators(.hidden)
    }

    private func footer(_ asked: WatchAsk.Asked, _ answer: WatchAnswer) -> String {
        if let when = asked.when { return "Asked \(AgeLabel.short(from: when)) ago · from your history" }
        return String(format: "%.1f s", Double(answer.milliseconds) / 1000)
    }

    private func failed(_ asked: WatchAsk.Asked) -> some View {
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
            WatchButton(title: "Retry", systemImage: "arrow.clockwise") { Task { await ask.ask(asked) } }
            WatchButton(title: "Back", systemImage: nil, quiet: true) { ask.reset() }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func problem(_ message: String) -> some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "mic.slash")
                .font(.title3)
                .foregroundStyle(Palette.amber)
            Text(message)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            WatchButton(title: "Try again", systemImage: "mic.fill") { Task { await ask.listen() } }
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

/// A small heading over a group on the Ask page.
private struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .textCase(.uppercase)
            .padding(.top, Spacing.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One earlier question: what was asked, where it was answered, and how long ago.
private struct RecentRow: View {
    let item: HistoryItem

    private var symbol: String {
        switch item.source {
        case .local: "lock.fill"
        case .muse: "cloud.fill"
        case .stub: "testtube.2"
        case .none: "info.circle"
        }
    }

    private var tint: Color {
        switch item.source {
        case .local: Palette.local
        case .muse: Palette.cloud
        case .stub, .none: Palette.amber
        }
    }

    static func spoken(_ item: HistoryItem) -> String {
        let tier = switch item.source {
        case .local: "answered on your phone"
        case .muse: "answered by Muse"
        case .stub: "answered by the offline stand-in"
        case .none: "no answer"
        }
        return "\(item.question), \(tier), \(AgeLabel.short(from: item.timestamp)) ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(item.question)
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            HStack(spacing: Spacing.xs) {
                Image(systemName: symbol).foregroundStyle(tint)
                if item.via.isVoice { Image(systemName: "mic.fill").foregroundStyle(Palette.textSecondary) }
                Text(AgeLabel.short(from: item.timestamp)).foregroundStyle(Palette.textSecondary)
            }
            .font(.caption2)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

/// The microphone while it is listening: a glow that swells with the voice.
private struct ListeningRing: View {
    let level: Double
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Palette.teal.opacity(0.6), Palette.teal.opacity(0)], center: .center,
                                     startRadius: 4, endRadius: 56))
                .scaleEffect(reduceMotion ? 0.95 : 0.8 + level * 0.5)
                .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0.3), value: level)
            Circle().stroke(Palette.teal.opacity(0.7), lineWidth: 4)
            Image(systemName: "mic.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Palette.textPrimary)
                .symbolEffect(.pulse, isActive: !reduceMotion)
        }
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
