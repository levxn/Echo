import SwiftUI

/// Shown once, the first time Echo opens: what it is, what stays on the phone, and why it asks for what it asks for.
struct WelcomeView: View {
    let onFinish: () -> Void
    /// `-welcome-page N` opens on page N (screenshots).
    @State private var page: Int = {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: "-welcome-page").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 0
    }()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Card: Identifiable {
        let id: Int
        let symbol: String?
        let title: String
        let message: String
        let points: [(symbol: String, text: String)]
    }

    private let cards = [
        Card(id: 0, symbol: nil, title: "A private memory for your day",
             message: "Your watch listens. Your phone remembers. Ask about any conversation, from today or from weeks ago.", points: []),
        Card(id: 1, symbol: "lock.shield.fill", title: "Your voice stays on your phone",
             message: "Speech becomes text on this phone, and the audio never leaves it.",
             points: [("text.bubble.fill", "Only when a question needs real synthesis, a few text snippets go to Meta's Muse Spark."),
                      ("list.bullet.rectangle.portrait.fill", "Every one is listed in your Privacy Ledger, exactly as sent."),
                      ("hand.raised.fill", "One switch turns the cloud off. You can forget the last few minutes, or the whole day.")]),
        Card(id: 2, symbol: "checkmark.seal.fill", title: "Permissions, only when needed",
             message: "Echo asks only for what it needs, when it needs it.",
             points: [("waveform", "Speech recognition turns your conversations into searchable text, on this phone."),
                      ("mic.fill", "The microphone lets you ask a question out loud."),
                      ("bell.fill", "Reminders and location are only asked for if you use them.")]),
    ]

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            AuroraBackground(calm: true)
            VStack(spacing: Spacing.xl) {
                TabView(selection: $page) {
                    ForEach(cards) { card in
                        cardView(card).tag(card.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .never))

                EchoButton(title: page == cards.count - 1 ? "Get started" : "Next", style: .prominent, tint: Palette.teal) {
                    if page == cards.count - 1 { onFinish() } else { withAnimation(reduceMotion ? nil : .smooth) { page += 1 } }
                }
                .padding(.horizontal, Spacing.xl)
                Button("Skip") { onFinish() }
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .opacity(page == cards.count - 1 ? 0 : 1)
                    .padding(.bottom, Spacing.lg)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func cardView(_ card: Card) -> some View {
        VStack(spacing: Spacing.xl) {
            Spacer(minLength: Spacing.xl)
            if let symbol = card.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 54, weight: .medium))
                    .foregroundStyle(Palette.accentGradient)
                    .frame(height: 108)
                    .accessibilityHidden(true)
            } else {
                IdleLogo(height: 100)
            }
            VStack(spacing: Spacing.md) {
                Text(card.title)
                    .font(.echoScreenTitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(card.message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !card.points.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    ForEach(card.points.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: Spacing.md) {
                            Image(systemName: card.points[i].symbol)
                                .foregroundStyle(Palette.teal)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(card.points[i].text)
                                .font(.subheadline)
                                .foregroundStyle(Palette.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()
            }
            Spacer(minLength: Spacing.xxl)
        }
        .padding(.horizontal, Spacing.xl)
    }
}

/// The welcome screen and the launch mark, laid over the app. Neither appears for a developer launch.
struct FirstImpression: ViewModifier {
    @State private var welcome = Welcome.isPending()
    @State private var mark = Welcome.showsLaunchMark()

    func body(content: Content) -> some View {
        content
            .overlay {
                if welcome {
                    WelcomeView {
                        Welcome.markSeen()
                        withAnimation(.easeOut(duration: 0.35)) { welcome = false }
                        // Asked here, after Echo has said why, rather than the moment the app opens.
                        Task { _ = await OnDeviceASR.authorize() }
                    }
                    .transition(.opacity)
                } else if mark {
                    LaunchMark(visible: $mark).transition(.opacity)
                }
            }
    }
}
