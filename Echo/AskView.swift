import SwiftUI

struct AskView: View {
    let ask: AskModel
    let voice: VoiceAskModel
    let history: AskHistoryModel
    let player: ChunkPlayer
    let hasMemory: Bool
    /// The day's moments, so a citation in a Muse answer can find its audio.
    let chunks: [ChunkRecord]
    /// Opens the Privacy tab, from a history entry.
    var onViewLedger: () -> Void = {}

    @FocusState private var focused: Bool
    @State private var sheet: HistoryRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    Color.clear.frame(height: 0).id("askTop")
                    field
                    VoiceCard(voice: voice, onStop: micTapped, onRetry: micTapped)
                    suggestions
                    result
                    followUpChips
                    HistorySection(history: history, onOpen: { sheet = HistoryRequest(open: .id($0.id)) },
                                   onSeeAll: { sheet = HistoryRequest() }, onAskAgain: { submit($0) },
                                   onDelete: { record in Task { await history.delete(id: record.id) } })
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xxl)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background { AuroraBackground() }
            .onChange(of: ask.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) { proxy.scrollTo(target, anchor: .top) }
            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: voice.state)
            .sheet(item: $sheet) { request in
                HistorySheet(history: history, chunks: chunks, player: player, open: request.open,
                             onAskAgain: { question in sheet = nil; submit(question) },
                             onViewLedger: { sheet = nil; onViewLedger() })
            }
            .task {
                // Dev hook: `-history all` / `-history first` opens the history sheet (or its newest entry) for screenshots.
                let args = ProcessInfo.processInfo.arguments
                guard let i = args.firstIndex(of: "-history"), i + 1 < args.count else { return }
                try? await Task.sleep(for: .milliseconds(900))
                sheet = HistoryRequest(open: args[i + 1] == "first" ? .first : .list)
            }
            // The demo driver opens the "What left your phone" panel, which sits below the answer's items.
            .onChange(of: ask.expandSent) { _, open in
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.8)) { proxy.scrollTo(open ? "sentPanel" : "askTop", anchor: open ? .center : .top) }
            }
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
            Button(action: micTapped) {
                Image(systemName: voice.state == .listening ? "stop.fill" : "mic.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(voice.state == .listening ? Palette.rose : Palette.teal)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(EchoPressStyle())
            .disabled(voice.state == .understanding)
            .accessibilityLabel(voice.state == .listening ? "Stop listening" : "Ask by voice")
            .accessibilityHint(voice.state == .listening ? "" : "Say your question")
            .accessibilityAddTraits(.startsMediaSession)
            Button { submit(ask.query) } label: {
                Image(systemName: "arrow.up")
                    .font(.subheadline.weight(.bold))
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
                    Button { submit(text, via: .suggestion) } label: {
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
        case .idle where !history.items.isEmpty:
            EmptyView()   // the history below is the prompt now
        case .idle:
            EmptyState(icon: hasMemory ? "sparkles" : "applewatch.radiowaves.left.and.right",
                       tint: hasMemory ? Palette.blue : Palette.amber,
                       title: hasMemory ? "Try a question above" : "Nothing to search yet",
                       message: hasMemory ? "Tap the mic and ask out loud, tap a suggestion, or type your own."
                                          : "Start the day on your watch. Conversations appear here once they have been transcribed.")
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
                .transition(.echoRise(reduceMotion: reduceMotion))
        case .sending(_, let plan, _):
            SendingCard(plan: plan, isStub: ask.isStub)
                .transition(.opacity)
        case .cloudAnswered(let r):
            CloudAnswerCard(result: r, expandSent: ask.expandSent, player: player) { item in
                CitationResolver.resolve(source: item.source, sourceTime: item.sourceTime, detail: item.detail + " " + item.title,
                                         snippets: r.plan.snippets, chunks: chunks)
            }
                .transition(.echoRise(reduceMotion: reduceMotion))
        case .cloudFailed(let f):
            CloudFailureCard(failure: f, player: player) { Task { await ask.retry() } }
                .transition(.opacity)
        }
    }

    /// Under an answer: what to ask next. (Idle shows the history instead.)
    private var followUps: (title: String, questions: [String]) {
        switch ask.state {
        case .answered(let r) where r.answer != nil:
            return ("Ask next", FollowUps.local(query: r.query, terms: r.answer?.highlightTerms ?? []))
        case .cloudAnswered(let r):
            return ("Ask next", FollowUps.cloud(r.answer, asked: r.query))
        default:
            return ("", [])
        }
    }

    @ViewBuilder
    private var followUpChips: some View {
        let next = followUps
        if !next.questions.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(next.title, style: .overline)
                ForEach(next.questions, id: \.self) { question in
                    Button { submit(question, via: .suggestion) } label: {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.teal)
                                .accessibilityHidden(true)
                            Text(question)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Palette.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(EchoPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
            .transition(.opacity)
        }
    }

    private func submit(_ text: String, via: AskVia = .typed) {
        focused = false
        player.stop()
        Task { await ask.ask(text, via: via) }
    }

    /// The mic: start listening, or (while listening) stop and go with what was heard.
    private func micTapped() {
        focused = false
        player.stop()
        Task { await voice.listen(ask: ask) }
    }
}
