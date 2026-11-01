import SwiftUI

extension WatchAnswer.Source {
    /// Where an answer came from, for the history's icons and labels.
    var historySymbol: String {
        switch self {
        case .local: "lock.fill"
        case .muse: "cloud.fill"
        case .stub: "testtube.2"
        case .none: "info.circle"
        }
    }

    var historyTint: Color {
        switch self {
        case .local: Palette.local
        case .muse: Palette.cloud
        case .stub, .none: Palette.amber
        }
    }

    var historyTitle: String {
        switch self {
        case .local: "Answered on this phone"
        case .muse: "Answered by Muse Spark"
        case .stub: "Stub preview · no API key"
        case .none: "No answer"
        }
    }
}

extension AskVia {
    var historySymbol: String {
        switch self {
        case .typed: "keyboard"
        case .suggestion: "sparkles"
        case .voice: "mic.fill"
        case .watch: "applewatch"
        case .watchVoice: "applewatch.radiowaves.left.and.right"
        }
    }
}

/// What the history sheet should show when it opens.
struct HistoryRequest: Identifiable {
    enum Open: Equatable { case list, first, id(String) }
    let id = UUID()
    var open: Open = .list
}

// MARK: Rows

/// One earlier question: where it was answered, the question, the start of its answer, and how long ago.
struct HistoryRow: View {
    let record: AskRecord

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: record.source.historySymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(record.source.historyTint)
                .frame(width: 28, height: 28)
                .background(record.source.historyTint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(record.question)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Text(record.shortAnswer)
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: Spacing.xs) {
                Text(AgeLabel.short(from: record.timestamp))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.textSecondary)
                if record.via != .typed {
                    Image(systemName: record.via.historySymbol)
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .echoRow()
        .contentShape(RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(record.question). \(record.source.historyTitle). \(AgeLabel.short(from: record.timestamp)) ago. \(record.shortAnswer)")
        .accessibilityHint("Shows the full answer")
    }
}

/// The last few questions on the Ask tab, with a way to see all of them.
struct HistorySection: View {
    let history: AskHistoryModel
    var limit = 4
    let onOpen: (AskRecord) -> Void
    let onSeeAll: () -> Void
    let onAskAgain: (String) -> Void
    let onDelete: (AskRecord) -> Void

    var body: some View {
        if !history.items.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "History", style: .overline) {
                    if history.items.count > limit {
                        Button("See all \(history.items.count)", action: onSeeAll)
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.teal)
                            .frame(minHeight: 44)
                    }
                }
                ForEach(history.items.prefix(limit)) { record in
                    Button { onOpen(record) } label: { HistoryRow(record: record) }
                        .buttonStyle(EchoPressStyle())
                        .contextMenu {
                            Button { onAskAgain(record.question) } label: { Label("Ask again", systemImage: "arrow.clockwise") }
                            Button(role: .destructive) { onDelete(record) } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
            .transition(.opacity)
        }
    }
}

// MARK: Sheet

/// Every question asked, newest first, grouped by day. Opening one shows the full answer, with its citations.
struct HistorySheet: View {
    let history: AskHistoryModel
    let chunks: [ChunkRecord]
    let player: ChunkPlayer
    let onAskAgain: (String) -> Void
    let onViewLedger: () -> Void

    @State private var selectedID: String?
    @State private var confirmClear = false
    @Environment(\.dismiss) private var dismiss
    private let initial: HistoryRequest.Open

    init(history: AskHistoryModel, chunks: [ChunkRecord], player: ChunkPlayer, open: HistoryRequest.Open = .list,
         onAskAgain: @escaping (String) -> Void, onViewLedger: @escaping () -> Void) {
        self.history = history; self.chunks = chunks; self.player = player
        self.onAskAgain = onAskAgain; self.onViewLedger = onViewLedger
        initial = open
        if case .id(let id) = open { _selectedID = State(initialValue: id) }
    }

    private var selected: AskRecord? { selectedID.flatMap { history.record(id: $0) } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                if let record = selected {
                    HistoryDetail(record: record, chunks: chunks, player: player,
                                  onAskAgain: onAskAgain, onViewLedger: onViewLedger,
                                  onDelete: { Task { await history.delete(id: record.id); selectedID = nil } })
                } else if history.items.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: "No questions yet",
                               message: "What you ask, and what you were told, is kept here on this phone until you clear it.")
                } else {
                    list
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground(calm: true) }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .onChange(of: history.items.count, initial: true) {
            if initial == .first, selectedID == nil, let first = history.items.first { selectedID = first.id }
        }
        .confirmationDialog("Clear your ask history?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { Task { await history.clear() } }
        } message: {
            Text("Deletes the questions you asked and the answers you got, on this phone. The privacy ledger is separate and stays.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            if selected != nil {
                Button { selectedID = nil } label: {
                    Label("History", systemImage: "chevron.backward")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Back to history")
            } else {
                Text("History")
                    .font(.echoSheetTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            Button("Done") { dismiss() }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.teal)
                .frame(minWidth: 44, minHeight: 44)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ForEach(HistoryGrouping.groups(history.items), id: \.title) { group in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(group.title, style: .overline)
                    ForEach(group.items) { record in
                        Button { selectedID = record.id } label: { HistoryRow(record: record) }
                            .buttonStyle(EchoPressStyle())
                            .contextMenu {
                                Button { onAskAgain(record.question) } label: { Label("Ask again", systemImage: "arrow.clockwise") }
                                Button(role: .destructive) { Task { await history.delete(id: record.id) } } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                }
            }
            EchoButton(title: "Clear history", systemImage: "trash", style: .destructive) { confirmClear = true }
        }
    }
}

// MARK: Detail

/// One stored question: when and how it was asked, the full answer, and the moments it came from (still playable).
struct HistoryDetail: View {
    let record: AskRecord
    let chunks: [ChunkRecord]
    let player: ChunkPlayer
    let onAskAgain: (String) -> Void
    let onViewLedger: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    private func chunk(_ id: String?) -> ChunkRecord? { id.flatMap { id in chunks.first { $0.id == id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(record.question)
                    .font(.echoAnswer)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                FlowLayout {
                    Chip(text: HistoryGrouping.when(record.timestamp), icon: "clock", tint: Palette.textSecondary)
                    Chip(text: record.via.label, icon: record.via.historySymbol, tint: Palette.blue)
                    if record.milliseconds > 0 {
                        Chip(text: String(format: "%.1f s", Double(record.milliseconds) / 1000), icon: "stopwatch", tint: Palette.textSecondary)
                    }
                }
            }

            answer

            VStack(spacing: Spacing.sm) {
                EchoButton(title: "Ask again", systemImage: "arrow.clockwise", style: .prominent, tint: Palette.teal) { onAskAgain(record.question) }
                EchoButton(title: "View in the ledger", systemImage: "lock.shield.fill", action: onViewLedger)
                EchoButton(title: "Delete this question", systemImage: "trash", style: .destructive) { confirmDelete = true }
            }
        }
        .confirmationDialog("Delete this question?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: onDelete)
        } message: {
            Text("It and its answer are removed from this phone. The privacy ledger keeps its own record.")
        }
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Label(record.detail.kind == .note ? "Not answered" : record.source.historyTitle, systemImage: record.source.historySymbol)
                .font(.echoLabel)
                .foregroundStyle(record.source.historyTint)

            if record.detail.kind == .note, let note = record.detail.note {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !record.detail.headline.isEmpty {
                Text(Highlighter.attributed(record.detail.headline, terms: record.detail.terms, highlight: Palette.teal, base: Palette.textPrimary))
                    .font(record.detail.kind == .note ? .subheadline : .echoAnswer)
                    .fixedSize(horizontal: false, vertical: true)
            } else if record.detail.kind != .note {
                Text(record.shortAnswer)
                    .font(.echoAnswer)
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !record.detail.items.isEmpty {
                VStack(spacing: Spacing.sm) {
                    ForEach(record.detail.items) { item in
                        HistoryItemRow(item: item, chunk: chunk(item.chunkID), player: player)
                    }
                }
            }

            let moments = record.detail.sourceChunkIDs.compactMap { chunk($0) }
            if !moments.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(record.detail.kind == .note ? "Closest moments" : "From these moments", style: .overline)
                    ForEach(moments) { MomentLine(chunk: $0, terms: record.detail.terms, player: player) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }
}

/// One cited item from a stored Muse answer; its audio plays if the moment is still on this phone.
private struct HistoryItemRow: View {
    let item: AskDetail.Item
    let chunk: ChunkRecord?
    let player: ChunkPlayer

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.footnote)
                        .foregroundStyle(Palette.textSecondary)
                }
                if !item.when.isEmpty { Chip(text: item.when, icon: "clock", tint: Palette.cloud) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SourcePlayChip(label: item.sourceTime, chunk: chunk, player: player)
        }
        .echoRow()
        .accessibilityElement(children: .contain)
    }
}

/// A moment on this phone: when, what was said, and a play button.
private struct MomentLine: View {
    let chunk: ChunkRecord
    let terms: [String]
    let player: ChunkPlayer

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(chunk.wallLabel)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .frame(width: 48, alignment: .leading)
            Text(Highlighter.attributed(chunk.transcript ?? "", terms: terms, highlight: Palette.teal, base: Palette.textSecondary))
                .font(.subheadline)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            PlayButton(isPlaying: player.playingID == chunk.id, label: "Play the audio from \(chunk.wallLabel)") { player.toggle(chunk) }
        }
        .echoRow()
        .accessibilityElement(children: .contain)
    }
}
