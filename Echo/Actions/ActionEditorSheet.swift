import SwiftUI
import UIKit

/// The review step: what Echo would do, written out so the person can change anything, and one button that does it.
/// Changes are kept as they go, so closing the sheet keeps the draft.
struct ActionEditorSheet: View {
    let item: ActionItem
    let chunks: [ChunkRecord]
    let onFinish: () -> Void

    @Environment(ActionsModel.self) private var actions
    @Environment(LedgerModel.self) private var ledger
    @Environment(\.dismiss) private var dismiss
    @State private var edits: ActionEdits

    init(item: ActionItem, chunks: [ChunkRecord], initialEdits: ActionEdits, onFinish: @escaping () -> Void) {
        self.item = item
        self.chunks = chunks
        self.onFinish = onFinish
        _edits = State(initialValue: initialEdits)
    }

    /// While a draft request waits for approval, the review is shown here instead of the form (a sheet can't open over another from the root).
    private var pendingReview: ReviewGate.Pending? { ledger.gate.pending.flatMap { $0.kind == .draft ? $0 : nil } }

    var body: some View {
        if let review = pendingReview {
            ReviewSheet(review: review, onSend: { ledger.gate.approve() }, onCancel: { ledger.gate.cancel() })
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                HStack {
                    Label(item.kind.label, systemImage: item.kind.symbol)
                        .font(.echoSheetTitle)
                        .foregroundStyle(Palette.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Close") { close() }
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minWidth: 44, minHeight: 44)
                }
                Text("“\(item.quote)”")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .echoCard()
                    .accessibilityLabel("You said: \(item.quote)")
                switch item.kind {
                case .email, .message, .waiting: MessageEditor(item: item, chunks: chunks, edits: $edits, onFinish: finish)
                case .calendar: CalendarEditor(item: item, edits: $edits, onFinish: finish)
                case .todo: TodoEditor(item: item, edits: $edits, onFinish: finish)
                case .shopping: ShoppingEditor(item: item, edits: $edits, onFinish: finish)
                case .call: CallEditor(item: item, edits: $edits, onFinish: finish)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.xl)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { AuroraBackground(calm: true) }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .interactiveDismissDisabled(false)
        .onDisappear { Task { await actions.saveEdits(item.id, edits) } }
    }

    private func close() { dismiss(); onFinish() }

    /// The action went where it was going: leave the sheet after a moment, so the confirmation can be read.
    private func finish() {
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            close()
        }
    }
}

// MARK: - Shared pieces

/// One line saying how it went, in words, with the way out when it didn't.
private struct OutcomeLine: View {
    let outcome: ActionPerformer.Outcome?

    var body: some View {
        if let outcome {
            Label(outcome.message, systemImage: outcome.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(outcome.succeeded ? Palette.teal : Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}

/// A labelled text field on a card.
private struct FieldRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label).font(Font.echoMeta.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            content
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .frame(minHeight: 44)
                .padding(.horizontal, Spacing.md)
                .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
    }
}

/// "Remind me later" as a button: the options are in an hour, tomorrow morning, and when it is due.
private struct NotifyMenu: View {
    let item: ActionItem
    let title: String
    @Binding var outcome: ActionPerformer.Outcome?
    @Environment(ActionPerformer.self) private var performer
    @Environment(ActionsModel.self) private var actions

    var body: some View {
        Menu {
            ForEach(ReminderOptions.options(due: item.dueText, now: actions.now())) { option in
                Button(option.title) { Task { outcome = await performer.notifyMe(item, at: option.date) } }
            }
            // A date well ahead: a reminder two days before as well, while there is still time to act.
            if let due = item.due, let before = Calendar.current.date(byAdding: .day, value: -2, to: due), before > actions.now().addingTimeInterval(3_600) {
                Button("Two days before · \(before.formatted(.dateTime.weekday(.abbreviated).hour().minute()))") {
                    Task { outcome = await performer.notifyMe(item, at: before) }
                }
            }
        } label: {
            Label(title, systemImage: "bell")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .contentShape(Capsule())
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// A sentence saying where the text goes, so nothing about the handoff is a surprise.
private struct StaysHere: View {
    let text: String
    var body: some View {
        Label(text, systemImage: "lock.fill").font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Message, email and follow-up

private struct MessageEditor: View {
    let item: ActionItem
    let chunks: [ChunkRecord]
    @Binding var edits: ActionEdits
    let onFinish: () -> Void

    @Environment(ActionsModel.self) private var actions
    @Environment(ActionPerformer.self) private var performer
    @Environment(DraftModel.self) private var drafts
    @Environment(LedgerModel.self) private var ledger
    @AppStorage(ProfileStore.museDraftsKey) private var museDrafts = true
    @State private var tone = DraftTone.friendly
    /// What was last written by the phone or by Muse: the body is the person's own once it differs.
    @State private var baseline: String
    @State private var writtenBy: Writer = .phone
    @State private var offered: MessageDraft?
    @State private var museNote: String?
    @State private var heldBack = 0
    enum Writer { case phone, muse }
    @Environment(\.openURL) private var openURL
    @State private var channel: MessageChannel
    @State private var to: String
    @State private var subject: String
    @State private var body_: String
    @State private var candidates: [ContactCard] = []
    @State private var chosen: ContactCard?
    @State private var toTyped = false
    @State private var outcome: ActionPerformer.Outcome?
    @State private var composer: Composer?
    @State private var copied = false

    enum Composer: Identifiable {
        case mail(to: [String], subject: String, body: String)
        case text(to: [String], body: String)
        var id: String { switch self { case .mail: "mail"; case .text: "text" } }
    }

    init(item: ActionItem, chunks: [ChunkRecord], edits: Binding<ActionEdits>, onFinish: @escaping () -> Void) {
        self.item = item
        self.chunks = chunks
        _edits = edits
        self.onFinish = onFinish
        let e = edits.wrappedValue
        _baseline = State(initialValue: e.bodyEditedByPerson ? "" : (e.body ?? ""))
        _writtenBy = State(initialValue: e.museAsked == true && !e.bodyEditedByPerson && e.body != nil ? .muse : .phone)
        let channel = e.channel ?? MessageTemplate.suggestedChannel(for: item)
        _channel = State(initialValue: channel)
        _to = State(initialValue: e.to ?? "")
        _toTyped = State(initialValue: e.to != nil)
        // The first draft is the instant one from this phone; a draft the person has already worked on takes its place.
        _subject = State(initialValue: e.subject ?? "")
        _body_ = State(initialValue: e.body ?? "")
    }

    private func template(_ channel: MessageChannel) -> MessageTemplate.Draft {
        MessageTemplate.draft(for: item, channel: channel, userName: actions.userName)
    }

    private var openTitle: String { "Open in \(channel.appName)" }
    private var openIcon: String { channel.symbol }
    private var placeholders: [String] { MessageTemplate.placeholders(in: body_) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            EchoSegmented(segments: MessageChannel.allCases.map { .init(value: $0, title: $0.title) }, selection: $channel)
            FieldRow(label: "To") {
                TextField("Name, \(channel == .email ? "email address" : "number")", text: $to)
                    .keyboardType(channel == .email ? .emailAddress : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if !candidates.isEmpty { contactChips }
            if channel == .email {
                FieldRow(label: "Subject") { TextField("Subject", text: $subject) }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Message").font(Font.echoMeta.weight(.semibold)).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button("Start again") { resetDraft() }
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: 44)
                }
                TextEditor(text: $body_)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 150)
                    .padding(Spacing.sm)
                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                    .accessibilityLabel("Message text")
            }
            if !placeholders.isEmpty {
                Label("Still to fill in: \(placeholders.joined(separator: ", "))", systemImage: "square.and.pencil")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            EchoButton(title: openTitle, systemImage: openIcon, style: .prominent, action: openIt)
            HStack(spacing: Spacing.sm) {
                Button { UIPasteboard.general.string = fullText; copied = true; Haptics.success() } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
                ShareAnswerButton(text: fullText)
            }
            OutcomeLine(outcome: outcome)
            if item.kind == .waiting { NotifyMenu(item: item, title: "Remind me to check", outcome: $outcome) }
            museSection
            StaysHere(text: "This draft is written on this phone and stays here. Echo opens \(channel.appName) with it filled in, and you press Send there.")
        }
        .onAppear { if body_.isEmpty { applyTemplate(for: channel) } }
        .onChange(of: channel) { _, new in
            edits.channel = new
            if !edits.bodyEditedByPerson { applyTemplate(for: new) } else if new != .email { subject = "" }
            refill()
        }
        .onChange(of: to) { _, new in edits.to = new }
        .onChange(of: subject) { _, new in edits.subject = new }
        .onChange(of: body_) { _, new in
            edits.body = new
            edits.bodyEditedByPerson = new != baseline
            copied = false
        }
        .task {
            // The address book is read on this phone, only now that a message is being written, and only for this one name.
            if to.isEmpty, let person = item.person {
                candidates = await performer.lookUp(person)
                if candidates.count == 1 { choose(candidates[0]) }
            }
            // The first draft is already on screen. If Muse is on and the person hasn't turned this off, a better one is being written.
            if museDrafts, edits.museAsked != true, !drafts.isStub, ledger.cloudEnabled, !ledger.reviewBeforeSend, !edits.bodyEditedByPerson {
                await askMuse()
            }
        }
        .sheet(item: $composer) { which in
            switch which {
            case .mail(let to, let subject, let body): MailComposer(to: to, subject: subject, body: body) { composed($0) }.ignoresSafeArea()
            case .text(let to, let body): MessageComposer(to: to, body: body) { composed($0) }.ignoresSafeArea()
            }
        }
    }

    private var fullText: String { channel == .email && !subject.isEmpty ? "\(subject)\n\n\(body_)" : body_ }

    private var contactChips: some View {
        FlowLayout {
            ForEach(candidates) { card in
                Button { choose(card) } label: {
                    Chip(text: card.name, icon: chosen?.id == card.id ? "checkmark.circle.fill" : "person.crop.circle", tint: chosen?.id == card.id ? Palette.teal : Palette.blue)
                        .frame(minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel("Use \(card.name)")
            }
        }
    }

    private func applyTemplate(for channel: MessageChannel) {
        let draft = template(channel)
        body_ = draft.body
        baseline = draft.body
        subject = draft.subject
        writtenBy = .phone
        offered = nil
        edits.bodyEditedByPerson = false
    }

    // MARK: Muse

    private var museSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if case .working(let plan) = drafts.state {
                HStack(spacing: Spacing.md) {
                    ProgressView().tint(Palette.cloud)
                    Text(drafts.isStub ? "Preparing a stub preview. Nothing is sent."
                         : "Muse is writing a better one" + (plan.heldBackCount > 0 ? ". \(plan.heldBackCount) sensitive detail\(plan.heldBackCount == 1 ? "" : "s") stay\(plan.heldBackCount == 1 ? "s" : "") on this phone." : "…"))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Label(writtenBy == .muse ? "Written by Muse Spark. Check it, and change anything." : "Written on this phone. Muse can write a better one.",
                      systemImage: writtenBy == .muse ? "cloud.fill" : "iphone")
                    .font(Font.echoMeta.weight(.semibold))
                    .foregroundStyle(writtenBy == .muse ? Palette.cloud : Palette.textSecondary)
                if heldBack > 0, writtenBy == .muse {
                    Label("\(heldBack) sensitive detail\(heldBack == 1 ? " was" : "s were") kept on this phone and put back in here.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(Palette.teal)
                }
                EchoSegmented(segments: DraftTone.allCases.map { .init(value: $0, title: $0.title) }, selection: $tone)
                EchoButton(title: writtenBy == .muse ? "Rewrite with Muse" : "Write it with Muse", systemImage: "cloud.fill", style: .secondary, tint: Palette.cloud) {
                    Task { await askMuse() }
                }
            }
            if let offered {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Muse wrote another version").font(Font.echoMeta.weight(.semibold)).foregroundStyle(Palette.cloud)
                    Text(offered.body).font(.footnote).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Use Muse's version") { use(offered) }
                            .font(.system(.footnote, design: .rounded, weight: .semibold)).foregroundStyle(Palette.cloud).frame(minHeight: 44)
                        Spacer()
                        Button("Keep mine") { self.offered = nil }
                            .font(.system(.footnote, design: .rounded, weight: .semibold)).foregroundStyle(Palette.textSecondary).frame(minHeight: 44)
                    }
                }
                .echoCard()
            }
            if let museNote { Label(museNote, systemImage: "info.circle").font(.footnote).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true) }
            Label(ledger.cloudEnabled ? "Muse sees this moment as text only, with passwords, numbers, emails and phone numbers swapped for placeholders. It is logged in your Privacy Ledger."
                                      : "Muse is off, so nothing leaves this phone.", systemImage: "lock.fill")
                .font(.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func museInstruction() -> String {
        let who = item.person.map { " to \($0)" } ?? ""
        let medium = channel == .email ? "email" : "text message"
        let when = item.dueText.map { " It is for \($0)." } ?? ""
        if item.kind == .waiting {
            return "Write a \(tone.instruction) \(medium)\(who) asking politely where this stands, because they said they would: “\(item.title)”.\(when)"
        }
        return "Write a \(tone.instruction) \(medium)\(who) that keeps this promise: “\(item.title)”.\(when)"
    }

    private func askMuse() async {
        edits.museAsked = true
        museNote = nil
        let channelKind: DraftChannel = channel == .email ? .email : .text
        heldBack = TierTwoPlanner.draftPlan(promise: item.asPromise, chunks: chunks, tone: tone, channel: channelKind, model: "", instruction: museInstruction()).heldBackCount
        drafts.reset()
        await drafts.generate(for: item.asPromise, tone: tone, channel: channelKind, chunks: chunks, instruction: museInstruction())
        switch drafts.state {
        case .ready(let ready):
            if edits.bodyEditedByPerson && body_ != baseline { offered = ready.draft } else { use(ready.draft) }
            if drafts.isStub { writtenBy = .phone; museNote = "Stub preview: no key is set, so this is canned text." }
        case .failed(let message): museNote = message
        case .cloudOff: museNote = "Muse is off, so the draft stays as it is."
        case .idle: break   // the person chose not to send it
        case .working: break
        }
        drafts.reset()
    }

    /// Muse's words go in as the new starting point; the details held back on this phone are already back in them.
    private func use(_ draft: MessageDraft) {
        body_ = draft.body
        baseline = draft.body
        if channel == .email, !draft.subject.isEmpty { subject = draft.subject }
        writtenBy = .muse
        offered = nil
        edits.bodyEditedByPerson = false
    }

    private func resetDraft() {
        applyTemplate(for: channel)
        edits.body = nil
        edits.subject = nil
        Haptics.success()
    }

    /// Puts the chosen contact's address in the "To" field, as the person's own typing doesn't get overwritten.
    private func choose(_ card: ContactCard) {
        chosen = card
        toTyped = false
        refill()
    }

    private func refill() {
        guard let chosen, !toTyped else { return }
        let value = channel == .email ? chosen.emails.first : chosen.phones.first
        to = value ?? ""
        if value == nil { outcome = .problem("No \(channel == .email ? "email address" : "number") is saved for \(chosen.name). Type one in.") } else if outcome?.succeeded == false { outcome = nil }
    }

    private func openIt() {
        var e = edits
        e.channel = channel; e.to = to; e.subject = subject; e.body = body_
        switch performer.plan(for: item, edits: e) {
        case .mailComposer(let to, let subject, let body): composer = .mail(to: to, subject: subject, body: body)
        case .messageComposer(let to, let body): composer = .text(to: to, body: body)
        case .open(let url, let app):
            openURL(url) { accepted in
                guard accepted else { outcome = .problem("\(app) couldn't be opened on this phone."); return }
                Task { await performer.handedOff(item, to: app); Haptics.success(); outcome = .done("Opened in \(app). Press Send there."); onFinish() }
            }
        case .unavailable(let message): outcome = .problem(message)
        }
    }

    private func composed(_ result: ComposeOutcome) {
        let app = channel == .email ? "Mail" : "Messages"
        composer = nil
        switch result {
        case .sent, .saved:
            Task { await performer.handedOff(item, to: app); Haptics.success(); outcome = .done(result == .sent ? "Sent from \(app)." : "Saved as a draft in \(app).") ; onFinish() }
        case .failed: outcome = .problem("\(app) couldn't send it. Your draft is still here.")
        case .cancelled: break
        }
    }
}

// MARK: - Calendar

private struct CalendarEditor: View {
    let item: ActionItem
    @Binding var edits: ActionEdits
    let onFinish: () -> Void

    @Environment(ActionsModel.self) private var actions
    @Environment(ActionPerformer.self) private var performer
    @State private var title: String
    @State private var start: Date
    @State private var allDay: Bool
    @State private var minutes: Int
    @State private var clashes: [String] = []
    @State private var outcome: ActionPerformer.Outcome?
    @State private var adding = false

    init(item: ActionItem, edits: Binding<ActionEdits>, onFinish: @escaping () -> Void) {
        self.item = item
        _edits = edits
        self.onFinish = onFinish
        _title = State(initialValue: item.title)
        _start = State(initialValue: item.due ?? Self.defaultStart())
        _allDay = State(initialValue: item.allDay)
        _minutes = State(initialValue: item.durationMinutes)
    }

    private static func defaultStart() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date())) ?? Date()
        return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private var edited: ActionItem {
        var e = item
        e.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? item.title : title
        e.due = start; e.allDay = allDay; e.durationMinutes = minutes; e.hasClock = !allDay
        return e
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FieldRow(label: "Title") { TextField("Title", text: $title) }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle("All day", isOn: $allDay).tint(Palette.teal).frame(minHeight: 44)
                DatePicker(allDay ? "Date" : "Starts", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                    .frame(minHeight: 44)
                if !allDay {
                    Picker("Length", selection: $minutes) {
                        ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { m in Text(Self.length(m)).tag(m) }
                    }
                    .frame(minHeight: 44)
                }
                if item.due == nil {
                    Label("No time was said. Pick one.", systemImage: "info.circle").font(.footnote).foregroundStyle(Palette.textSecondary)
                } else if let said = item.dueText {
                    Label("You said: \(said)", systemImage: "quote.opening").font(.footnote).foregroundStyle(Palette.textSecondary)
                }
                if item.repeatsYearly {
                    Label("Repeats every year.", systemImage: "repeat").font(.footnote).foregroundStyle(Palette.teal)
                }
            }
            .font(.system(.body, design: .rounded, weight: .medium))
            .foregroundStyle(Palette.textPrimary)
            .echoCard()
            if !clashes.isEmpty {
                Label("You already have \(clashes.prefix(2).map { "“\($0)”" }.joined(separator: " and ")) at that time.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            EchoButton(title: adding ? "Adding…" : "Add to Calendar", systemImage: "calendar.badge.plus", style: .prominent, tint: Palette.blue) {
                adding = true
                Task {
                    outcome = await performer.addToCalendar(edited)
                    adding = false
                    if outcome?.succeeded == true { Haptics.success(); onFinish() }
                }
            }
            .disabled(adding)
            OutcomeLine(outcome: outcome)
            StaysHere(text: "The event goes straight into your calendar when you tap. Your calendar is read only to check for a clash, and never leaves this phone.")
        }
        .onChange(of: title) { _, v in edits.title = v }
        .onChange(of: start) { _, v in edits.due = v; edits.noDate = false }
        .onChange(of: allDay) { _, v in edits.allDay = v }
        .onChange(of: minutes) { _, v in edits.durationMinutes = v }
        .task(id: "\(start.timeIntervalSince1970)-\(minutes)-\(allDay)") { clashes = await performer.conflicts(for: edited) }
    }

    private static func length(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) minutes" : (minutes % 60 == 0 ? "\(minutes / 60) hour\(minutes == 60 ? "" : "s")" : "\(minutes / 60)½ hours")
    }
}

// MARK: - To-do

private struct TodoEditor: View {
    let item: ActionItem
    @Binding var edits: ActionEdits
    let onFinish: () -> Void

    @Environment(ActionPerformer.self) private var performer
    @State private var title: String
    @State private var hasDate: Bool
    @State private var due: Date
    @State private var outcome: ActionPerformer.Outcome?

    init(item: ActionItem, edits: Binding<ActionEdits>, onFinish: @escaping () -> Void) {
        self.item = item
        _edits = edits
        self.onFinish = onFinish
        _title = State(initialValue: item.title)
        _hasDate = State(initialValue: item.due != nil)
        _due = State(initialValue: item.due ?? Date().addingTimeInterval(3_600))
    }

    private var edited: ActionItem {
        var e = item
        e.title = title.trimmingCharacters(in: .whitespaces).isEmpty ? item.title : title
        e.due = hasDate ? due : nil
        e.hasClock = hasDate && (item.hasClock || due != item.due)
        return e
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            FieldRow(label: "To-do") { TextField("What to do", text: $title) }
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Toggle("Due date", isOn: $hasDate).tint(Palette.teal).frame(minHeight: 44)
                if hasDate { DatePicker("Due", selection: $due, displayedComponents: [.date, .hourAndMinute]).frame(minHeight: 44) }
                if let said = item.dueText { Label("You said: \(said)", systemImage: "quote.opening").font(.footnote).foregroundStyle(Palette.textSecondary) }
            }
            .font(.system(.body, design: .rounded, weight: .medium))
            .foregroundStyle(Palette.textPrimary)
            .echoCard()
            EchoButton(title: "Add to Reminders", systemImage: "checklist", style: .prominent, tint: Palette.amber) {
                Task { outcome = await performer.addToReminders(edited); if outcome?.succeeded == true { Haptics.success(); onFinish() } }
            }
            NotifyMenu(item: edited, title: "Notify me from Echo", outcome: $outcome)
            OutcomeLine(outcome: outcome)
            StaysHere(text: "The to-do goes into the Reminders app, or Echo can notify you itself. Both stay on this phone.")
        }
        .onChange(of: title) { _, v in edits.title = v }
        .onChange(of: hasDate) { _, v in if v { edits.due = due; edits.noDate = false } else { edits.noDate = true } }
        .onChange(of: due) { _, v in edits.due = v; edits.noDate = false }
    }
}

// MARK: - Shopping list

private struct ShoppingEditor: View {
    let item: ActionItem
    @Binding var edits: ActionEdits
    let onFinish: () -> Void

    @Environment(ActionPerformer.self) private var performer
    @State private var items: [String]
    @State private var outcome: ActionPerformer.Outcome?

    init(item: ActionItem, edits: Binding<ActionEdits>, onFinish: @escaping () -> Void) {
        self.item = item
        _edits = edits
        self.onFinish = onFinish
        _items = State(initialValue: item.items)
    }

    private var edited: ActionItem {
        var e = item
        e.items = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return e
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader("Items", meta: "\(edited.items.count)", style: .overline)
                ForEach(items.indices, id: \.self) { i in
                    HStack(spacing: Spacing.sm) {
                        TextField("Item", text: $items[i])
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(minHeight: 44)
                        Button { items.remove(at: i) } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Palette.rose).frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Remove \(items[i])")
                    }
                    .padding(.leading, Spacing.md)
                    .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                }
                Button { items.append("") } label: {
                    Label("Add an item", systemImage: "plus.circle.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minHeight: 44)
                }
            }
            EchoButton(title: "Add to Reminders", systemImage: "cart.badge.plus", style: .prominent, tint: Palette.amber) {
                Task { outcome = await performer.addToReminders(edited); if outcome?.succeeded == true { Haptics.success(); onFinish() } }
            }
            ShareAnswerButton(text: edited.items.map { "• \($0)" }.joined(separator: "\n"))
            OutcomeLine(outcome: outcome)
            StaysHere(text: "Each item becomes a to-do in a Reminders list called Shopping, on this phone.")
        }
        .onChange(of: items) { _, v in edits.items = v }
    }
}

// MARK: - Call

private struct CallEditor: View {
    let item: ActionItem
    @Binding var edits: ActionEdits
    let onFinish: () -> Void

    @Environment(ActionPerformer.self) private var performer
    @Environment(\.openURL) private var openURL
    @State private var number: String
    @State private var candidates: [ContactCard] = []
    @State private var outcome: ActionPerformer.Outcome?

    init(item: ActionItem, edits: Binding<ActionEdits>, onFinish: @escaping () -> Void) {
        self.item = item
        _edits = edits
        self.onFinish = onFinish
        _number = State(initialValue: edits.wrappedValue.to ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text(item.title).font(.echoAnswer).foregroundStyle(Palette.textPrimary).fixedSize(horizontal: false, vertical: true)
            FieldRow(label: "Number") {
                TextField("Phone number", text: $number).keyboardType(.phonePad)
            }
            if !candidates.isEmpty {
                FlowLayout {
                    ForEach(candidates) { card in
                        ForEach(card.phones, id: \.self) { phone in
                            Button { number = phone } label: {
                                Chip(text: "\(card.name) · \(phone)", icon: "phone.fill", tint: number == phone ? Palette.teal : Palette.blue).frame(minHeight: 44)
                            }
                            .buttonStyle(EchoPressStyle())
                        }
                    }
                }
            }
            EchoButton(title: "Call", systemImage: "phone.fill", style: .prominent) {
                guard case .open(let url, let app) = HandoffPlan.call(number) else { outcome = .problem("There is no number to call yet. Add one first."); return }
                openURL(url) { ok in
                    guard ok else { outcome = .problem("This phone can't place a call."); return }
                    Task { await performer.handedOff(item, to: app); Haptics.success(); onFinish() }
                }
            }
            NotifyMenu(item: item, title: "Remind me to call", outcome: $outcome)
            OutcomeLine(outcome: outcome)
            StaysHere(text: "The number is looked up in your contacts on this phone. Nothing about your contacts is sent anywhere.")
        }
        .onChange(of: number) { _, v in edits.to = v }
        .task {
            // The address book is read on this phone, for this one name, now that a call is being set up.
            guard number.isEmpty else { return }
            let name = item.person ?? Self.callName(item.title)
            guard let name, !name.isEmpty else { return }
            candidates = await performer.lookUp(name)
            if candidates.count == 1, let phone = candidates[0].phones.first { number = phone }
        }
    }

    /// "Call Grandma this Sunday" → "Grandma".
    private static func callName(_ title: String) -> String? { ActionClassifier.callTargetName(in: title, contextName: nil) }
}
