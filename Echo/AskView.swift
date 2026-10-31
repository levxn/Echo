import SwiftUI

struct AskView: View {
    let ask: AskModel
    let player: ChunkPlayer
    let hasMemory: Bool

    @FocusState private var focused: Bool

    private static let suggestions = [
        "When is the plumber coming?",
        "What did Mister Brennan say about the lease?",
        "Where is Priya going in March?",
        "What did I promise people today?",
        "Summarize my day",
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header.id("askTop")
                    field
                    suggestions
                    result
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background { AuroraBackground() }
            // The demo driver opens the "What left your phone" panel, which sits below the answer's items.
            .onChange(of: ask.expandSent) { _, open in
                withAnimation(.smooth(duration: 0.8)) { proxy.scrollTo(open ? "sentPanel" : "askTop", anchor: open ? .center : .top) }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask your day")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Text("Answers come from this phone first. Only questions that need synthesis ever reach the cloud.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var field: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Palette.textSecondary)
            TextField("Ask about today…", text: Bindable(ask).query)
                .focused($focused)
                .submitLabel(.search)
                .foregroundStyle(Palette.textPrimary)
                .onSubmit { submit(ask.query) }
            Button { submit(ask.query) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Palette.background)
                    .frame(width: 32, height: 32)
                    .background(Palette.accentGradient, in: Circle())
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(EchoPressStyle())
            .disabled(ask.query.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Ask")
        }
        .padding(.leading, Spacing.lg)
        .padding(.trailing, Spacing.xs)
        .frame(minHeight: 52)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var suggestions: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Spacing.sm) {
                ForEach(Self.suggestions, id: \.self) { text in
                    Button { submit(text) } label: {
                        Text(text)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Palette.textPrimary)
                            .padding(.horizontal, Spacing.md)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(EchoPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var result: some View {
        switch ask.state {
        case .idle:
            VStack(spacing: Spacing.sm) {
                Image(systemName: hasMemory ? "sparkles" : "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 28))
                    .foregroundStyle(hasMemory ? Palette.blue : Palette.amber)
                Text(hasMemory ? "Try a question above" : "Nothing to search yet")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textPrimary)
                Text(hasMemory ? "Echo searches transcripts stored on this phone: keywords and meaning together."
                               : "Start the day on your watch. Conversations appear here once they have been transcribed.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .echoCard(padding: Spacing.xl)
        case .searching(let q):
            HStack(spacing: Spacing.md) {
                ProgressView().tint(Palette.teal)
                Text("Searching “\(q)”")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard()
        case .answered(let r):
            AnswerCard(result: r, player: player)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .sending(_, let plan, _):
            SendingCard(plan: plan, isStub: ask.isStub)
                .transition(.opacity)
        case .cloudAnswered(let r):
            CloudAnswerCard(result: r, expandSent: ask.expandSent)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .cloudFailed(let f):
            CloudFailureCard(failure: f, player: player) { Task { await ask.retry() } }
                .transition(.opacity)
        }
    }

    private func submit(_ text: String) {
        focused = false
        player.stop()
        withAnimation(.spring(duration: 0.4, bounce: 0.1)) { }
        Task { await ask.ask(text) }
    }
}
