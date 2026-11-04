import SwiftUI

/// Everything said that is worth acting on, with the draft for each one to review and edit before it goes anywhere.
struct ActionsView: View {
    let model: PipelineModel
    let player: ChunkPlayer
    @Environment(ActionsModel.self) private var actions
    @Environment(PlacesModel.self) private var places
    @Environment(VoiceBookModel.self) private var voices
    @Environment(MuseActionsModel.self) private var muse
    @Environment(LedgerModel.self) private var ledger
    @State private var filter = ActionFilter.all
    @State private var editing: ActionItem?
    @State private var showDone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var groups: [ActionsModel.Group] { actions.groups(filter) }
    private var filterSegments: [EchoSegmented<ActionFilter>.Segment] {
        ActionFilter.allCases.filter { $0 == .all || $0 == filter || actions.count($0) > 0 }.map { f in
            .init(value: f, title: f == .waiting ? "Waiting" : f.title, badge: f != .all && actions.count(f) > 0 ? actions.count(f) : nil,
                  spoken: "\(actions.count(f)) to review")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                if actions.pendingCount > 0 || filter != .all { EchoSegmented(segments: filterSegments, selection: $filter) }
                if groups.isEmpty {
                    EmptyState(icon: "checklist", tint: Palette.teal,
                               title: actions.pendingCount == 0 ? "Nothing to review yet" : "Nothing here",
                               message: actions.pendingCount == 0 ? "Things you say you will do, and things people ask of you, show up here as they are said."
                                                                   : "Nothing of this kind is waiting. Try another filter.")
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        SectionHeader(group.section.title, meta: "\(group.items.count)", style: .overline)
                        ForEach(group.items) { item in card(item, section: group.section) }
                    }
                }
                findMore
                if !actions.done.isEmpty { doneSection }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
            .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: actions.pendingCount)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .sheet(item: $editing) { item in
            ActionEditorSheet(item: item, chunks: model.chunks, initialEdits: actions.edits(for: item.id), onFinish: { editing = nil })
        }
        .onChange(of: actions.openRequest) { _, id in editing = id.flatMap { id in actions.items.first { $0.id == id } } }
        .onChange(of: editing) { _, now in if now == nil { actions.openRequest = nil } }
        .task {
            // Dev hook: `-action-open N` (or `message`) opens an action's editor (screenshots).
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-action-open"), i + 1 < args.count else { return }
            try? await Task.sleep(for: .seconds(1.5))
            let all = actions.groups(.all).flatMap(\.items)
            // `-action-open message` opens the first email or message; a number opens that position in the list.
            if args[i + 1] == "message" { editing = all.first { $0.kind == .message || $0.kind == .email } }
            else if let n = Int(args[i + 1]), all.indices.contains(n) { editing = all[n] }
        }
    }

    /// What needs attention first: "2 overdue · 3 due today". Nothing when nothing is.
    private var dueSummary: String? {
        let groups = actions.groups(.all)
        let overdue = groups.first { $0.section == .overdue }?.items.count ?? 0
        let today = groups.first { $0.section == .today }?.items.count ?? 0
        let parts = [overdue > 0 ? "\(overdue) overdue" : nil, today > 0 ? "\(today) due today" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(actions.pendingCount == 0 ? "All caught up" : "\(actions.pendingCount) to review")
                .font(.echoSheetTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let due = dueSummary {
                Text(due)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Muse as a second pair of eyes, always the person's choice: a button, never automatic.
    private var findMore: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Missed something?", style: .overline)
            switch muse.state {
            case .working(let snippets, let held):
                HStack(spacing: Spacing.md) {
                    ProgressView().tint(Palette.cloud)
                    Text("Muse is reading \(snippets) moment\(snippets == 1 ? "" : "s")" + (held > 0 ? ". \(held) sensitive detail\(held == 1 ? "" : "s") stay\(held == 1 ? "s" : "") on this phone." : "…"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            default:
                EchoButton(title: "Find more with Muse", systemImage: "magnifyingglass", style: .secondary, tint: Palette.cloud) { findWithMuse() }
                    .disabled(!ledger.cloudEnabled || model.storedCount == 0)
                    .opacity(ledger.cloudEnabled && model.storedCount > 0 ? 1 : 0.5)
                if let note = museNote { Label(note.text, systemImage: note.icon).font(.footnote.weight(.medium)).foregroundStyle(note.tint).fixedSize(horizontal: false, vertical: true) }
            }
            Label(ledger.cloudEnabled
                  ? (ledger.reviewBeforeSend ? "You see exactly what is sent first. Text only: passwords, numbers, emails and phone numbers are swapped for placeholders on this phone."
                                             : "Text only, logged in your Privacy Ledger. Passwords, numbers, emails and phone numbers are swapped for placeholders on this phone first.")
                  : "Muse is off, so nothing leaves this phone. Turn it on in the You tab to look for more.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }

    private var museNote: (text: String, icon: String, tint: Color)? {
        switch muse.state {
        case .done(let found, let stub): (stub ? "Stub preview: nothing was sent, and nothing new was invented." : found == 0 ? "Muse found nothing more." : "Muse found \(found) more.", "checkmark.circle.fill", Palette.teal)
        case .declined: ("Nothing was sent.", "hand.raised.fill", Palette.textSecondary)
        case .failed(let message): (message, "exclamationmark.triangle.fill", Palette.amber)
        case .cloudOff, .idle, .working: nil
        }
    }

    private func findWithMuse() {
        let day = model.chunks.map(\.dayId).max() ?? DayID.today()
        Task {
            let added = await muse.find(chunks: model.chunks, day: day, actions: actions, userName: actions.userName, myVoice: voices.me?.id, voiceNames: voices.nameMap)
            if added > 0 { Haptics.success() }
        }
    }

    private func card(_ item: ActionItem, section: ActionsModel.Section) -> some View {
        let chunk = model.record(id: item.chunkID)
        return ActionCard(item: item, section: section, now: actions.now(), place: chunk.flatMap { places.label(for: $0) },
                          speakerName: voices.voice(id: item.speakerId).map { $0.isMe ? "You" : $0.display },
                          playing: player.playingID == item.chunkID,
                          onOpen: { editing = item },
                          onPlay: { if let chunk { player.toggle(chunk) } },
                          onDone: { Task { await actions.markDone(item.id) } },
                          onDismiss: { Task { await actions.dismiss(item.id) } },
                          onLater: { date in Task { await actions.snooze(item.id, until: date) } })
            .transition(.opacity)
    }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { showDone.toggle() } } label: {
                HStack {
                    SectionHeader("Done", meta: "\(actions.done.count)", style: .overline)
                    Image(systemName: showDone ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showDone ? "Hides what is done" : "Shows what is done")
            if showDone {
                ForEach(actions.done) { item in
                    DoneActionRow(item: item, via: actions.state(of: item.id)?.handedOffVia) { Task { await actions.restore(item.id) } }
                }
            }
        }
    }
}

extension VoiceBookModel {
    /// Voice id to the name the person gave it.
    var nameMap: [String: String] { Dictionary(voices.compactMap { v in v.name.map { (v.id, $0) } }, uniquingKeysWith: { a, _ in a }) }
}
