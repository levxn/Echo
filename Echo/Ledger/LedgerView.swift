import SwiftUI

/// The You tab: who you are, what stayed on the phone and what left it, every switch in one place, and your data.
struct YouView: View {
    @Bindable var profile: ProfileStore
    let listening: ListeningStore
    let ledger: LedgerModel
    let model: PipelineModel
    let history: AskHistoryModel
    let privacy: RecordingPrivacy
    @Binding var page: Page?
    /// Forgets the last N minutes of what was heard; says how many moments went.
    let onForgetRecent: (Int) async -> Int
    /// Wipes the day (and optionally the ledger); owned by RootView because it touches every model.
    let onForget: (_ includeLedger: Bool) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmClear = false
    @State private var confirmForget = false
    @State private var confirmClearHistory = false
    @State private var forgetMinutes: Int?
    @State private var forgotten: String?
    @AppStorage(Retention.key) private var retentionDays = Retention.defaultDays
    @AppStorage(OnDevicePreference.key) private var preferOnDevice = false
    @State private var showAllActivity = false
    @State private var showProfile = false
    @State private var exportURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(BriefingCenter.self) private var briefings

    /// The sections of settings, each on a page of its own so none of them is a long scroll.
    enum Page: String, CaseIterable, Identifiable {
        case muse, listening, helpers, kept, sent, data
        var id: String { rawValue }
        var title: String {
            switch self {
            case .muse: "Muse and privacy"
            case .listening: "Listening"
            case .helpers: "Helpers"
            case .kept: "What Echo kept"
            case .sent: "What was sent"
            case .data: "Your data"
            }
        }
        var symbol: String {
            switch self {
            case .muse: "lock.shield.fill"
            case .listening: "waveform"
            case .helpers: "wand.and.stars"
            case .kept: "chart.bar.fill"
            case .sent: "paperplane.fill"
            case .data: "internaldrive.fill"
            }
        }
    }

    /// Activity shows this many entries until "Show all" is tapped.
    static let activityLimit = 3

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Color.clear.frame(height: 0).id("ledgerTop")
                if let page { detail(page) } else { overview }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .sheet(isPresented: $showProfile) { ProfileEditSheet(profile: profile) }
        .onChange(of: page) { proxy.scrollTo("ledgerTop", anchor: .top) }
        .task(id: ledger.focus) {
            // The demo and the dev hooks ask for a place by name: "yourData" is its own page now.
            guard let target = ledger.focus else { return }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { page = target == "yourData" ? .data : Page(rawValue: target) }
        }
        .onChange(of: ledger.entries, initial: true) { refreshExport() }
        .confirmationDialog("Forget the day?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget the day", role: .destructive) { onForget(false) }
            Button("Forget the day and the ledger", role: .destructive) { onForget(true) }
        } message: {
            Text("Deletes every transcript, audio clip, summary and checked-off commitment on this phone. Your API key and settings stay. The ledger stays too, unless you choose to forget it.")
        }
        .confirmationDialog("Forget the last few minutes?", isPresented: Binding(get: { forgetMinutes != nil }, set: { if !$0 { forgetMinutes = nil } }),
                            titleVisibility: .visible, presenting: forgetMinutes) { minutes in
            Button("Forget the last \(ForgetWindow.title(minutes: minutes))", role: .destructive) {
                Task {
                    let count = await onForgetRecent(minutes)
                    forgotten = count == 0 ? "There was nothing to forget." : "Forgot \(count) moment\(count == 1 ? "" : "s")."
                }
            }
        } message: { minutes in
            Text("Deletes what was heard in the last \(ForgetWindow.title(minutes: minutes)) of what was captured: its transcripts, audio, any answers that used it, and that day's summary. The ledger keeps its record of what was sent.")
        }
        .confirmationDialog("Clear your ask history?", isPresented: $confirmClearHistory, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { Task { await history.clear() } }
        } message: {
            Text("Deletes the questions you asked and the answers you got, on this phone. The privacy ledger is separate and stays.")
        }
        .confirmationDialog("Clear the privacy ledger?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear ledger", role: .destructive) { Task { await ledger.clear() } }
        } message: {
            Text("This deletes the record of what was sent. It can't be undone.")
        }
        }
    }

    private func refreshExport() {
        guard !ledger.entries.isEmpty else { exportURL = nil; return }
        exportURL = try? LedgerExport(entries: ledger.entries).write(into: FileManager.default.temporaryDirectory)
    }

    // MARK: Settings

    /// One group of switches on a card.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Spacing.md) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard()
    }

    // MARK: Overview and pages

    private var overview: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            ProfileCard(profile: profile) { showProfile = true }
            SummaryCard(totals: ledger.totals)
            VStack(spacing: Spacing.sm) {
                ForEach(Page.allCases) { p in sectionRow(p) }
            }
            EchoButton(title: "How Echo works", systemImage: "square.stack.3d.up.fill") { ledger.showArchitecture = true }
        }
    }

    private func sectionRow(_ p: Page) -> some View {
        Button { withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { page = p } } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: p.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.teal)
                    .frame(width: 36, height: 36)
                    .background(Palette.teal.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(p.title).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text(summary(of: p)).font(.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                Spacer(minLength: Spacing.sm)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .echoRow(horizontal: Spacing.md, vertical: Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(EchoPressStyle())
        .accessibilityLabel("\(p.title), \(summary(of: p))")
    }

    /// One line saying how the section is set right now, so most of the time there is no need to open it.
    private func summary(of p: Page) -> String {
        switch p {
        case .muse: ledger.cloudEnabled ? (ledger.reviewBeforeSend ? "On · you approve each request" : "On") : "Off · nothing is sent"
        case .listening: listening.settings.title
        case .helpers:
            "\([profile.catchPromises, briefings.enabled, profile.actionsMorning, profile.journalReminder, profile.speakVoiceAnswers].filter { $0 }.count) of 5 on"
        case .kept: model.recordedSeconds > 0 ? "\(Format.clock(model.phoneConfirmedSeconds)) of \(Format.clock(max(model.recordedSeconds, model.watchKeptSeconds))) saved" : "Nothing yet"
        case .sent: ledger.entries.isEmpty ? "Nothing yet" : "\(ledger.entries.count) request\(ledger.entries.count == 1 ? "" : "s")"
        case .data: "Keeps \(Retention.title(days: retentionDays).lowercased())"
        }
    }

    private func detail(_ p: Page) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text(p.title)
                .font(.echoSheetTitle)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            switch p {
            case .muse: museAndPrivacy
            case .listening: listeningGroup
            case .helpers: helpers
            case .kept: FunnelCard(model: model, alwaysFull: true)
            case .sent: activity
            case .data: yourData.id("yourData")
            }
        }
    }

    private var divider: some View { Divider().overlay(Palette.stroke) }

    private var museAndPrivacy: some View {
        group {
            ToggleRow(title: "Allow Muse for broad questions", systemImage: "cloud.fill",
                      caption: ledger.cloudEnabled ? "Broad questions go to Muse Spark as text. Audio never does."
                                                   : "Off: nothing is sent. Broad questions show the closest moments here.",
                      isOn: Bindable(ledger).cloudEnabled)
            if SystemLocalBrain().isAvailable {
                divider
                ToggleRow(title: "Keep answers on this phone", systemImage: "cpu",
                          caption: preferOnDevice ? "Broad questions are answered by this phone's own model, so nothing is sent. Muse is used only if it can't."
                                                  : "Off: broad questions go to Muse Spark. With the cloud switched off, this phone's model answers instead.",
                          isOn: $preferOnDevice, tint: Palette.local)
            }
            divider
            ToggleRow(title: "Review before sending", systemImage: "eye",
                      caption: ledger.reviewBeforeSend ? "You see the exact text first, then choose Send or Don't send."
                                                       : "Off: sent as soon as you ask, and logged here.",
                      isOn: Bindable(ledger).reviewBeforeSend)
            divider
            ToggleRow(title: "Mask names before sending", systemImage: "theatermasks",
                      caption: ledger.maskNames ? "Names become [PERSON_1] on this phone and return in the answer. Best effort."
                                                : "Off: names are sent as spoken.",
                      isOn: Bindable(ledger).maskNames)
            divider
            ToggleRow(title: "Let Muse write my drafts", systemImage: "square.and.pencil",
                      caption: "When you open a message in Actions, Muse writes a better version. It only sees that moment, with passwords, numbers, emails and phone numbers swapped for placeholders; your words go back in on this phone.",
                      isOn: $profile.museDrafts, tint: Palette.cloud)
        }
    }

    private var listeningGroup: some View {
        group {
            ListeningCard(model: model, listening: listening)
            divider
            ToggleRow(title: "Announce recording", systemImage: "applewatch.radiowaves.left.and.right",
                      caption: privacy.announce ? "The watch buzzes every 10 minutes while it listens, so people nearby aren't unaware."
                                                : "Off: the watch listens silently. Say “off the record” any time to pause.",
                      isOn: Bindable(privacy).announce, tint: Palette.teal)
        }
    }

    private var helpers: some View {
        group {
            ToggleRow(title: "Catch promises as I say them", systemImage: "checkmark.circle.fill",
                      caption: "When you say you will do something, your watch shows “Got it” and you can tap Keep for a reminder.",
                      isOn: $profile.catchPromises, tint: Palette.teal)
            divider
            ToggleRow(title: "Brief me before meetings", systemImage: "calendar.badge.clock",
                      caption: briefings.enabled ? "Looks at who you are meeting in your calendar, on this phone, and reminds you what you owe them 15 minutes before."
                                                 : "Off. Turning it on asks to read your calendar. Nothing from it is sent anywhere.",
                      isOn: Bindable(briefings).enabled, tint: Palette.teal)
            divider
            ToggleRow(title: "Morning summary of actions", systemImage: "sunrise.fill",
                      caption: "A nudge at 8 am saying how many things are waiting in Actions. It says nothing about what they are.",
                      isOn: $profile.actionsMorning, tint: Palette.teal)
            divider
            ToggleRow(title: "Remind me to write my journal", systemImage: "book.closed.fill",
                      caption: "A nudge at 9 pm. It says nothing about your day, and nothing is written or sent until you ask.",
                      isOn: $profile.journalReminder, tint: Palette.teal)
            divider
            ToggleRow(title: "Speak answers to voice questions", systemImage: "speaker.wave.2.fill",
                      caption: "When you ask out loud, the answer is read back to you. Every answer also has a Read aloud button.",
                      isOn: $profile.speakVoiceAnswers, tint: Palette.teal)
        }
    }

    // MARK: Activity

    @ViewBuilder
    private var activity: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            if ledger.entries.isEmpty {
                EmptyState(icon: "lock.shield", tint: Palette.teal, title: "Nothing recorded yet",
                           message: "Ask a question and it appears here, along with whether anything left your phone.")
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(Capped.visible(ledger.entries, limit: Self.activityLimit, showAll: showAllActivity)) { EntryRow(entry: $0) }
                }
                ShowMoreButton(total: ledger.entries.count, limit: Self.activityLimit, isExpanded: $showAllActivity)
            }
        }
    }

    // MARK: Your data

    private var yourData: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Everything Echo keeps is on this phone. Export the ledger, or erase what you don't want kept.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // With very large text the value drops below the title instead of squeezing it to one word per line.
            let retentionLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.xs))
                                                               : AnyLayout(HStackLayout(spacing: Spacing.md))
            retentionLayout {
                if !typeSize.isAccessibilitySize { Image(systemName: "calendar.badge.clock").font(.subheadline.weight(.semibold)).frame(width: 22) }
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Keep memories for").font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text("Older days are forgotten automatically.").font(.caption).foregroundStyle(Palette.textSecondary)
                }
                if !typeSize.isAccessibilitySize { Spacer() }
                Menu {
                    Picker("Keep memories for", selection: $retentionDays) {
                        ForEach(Retention.options, id: \.days) { Text($0.title).tag($0.days) }
                    }
                } label: {
                    Text(Retention.title(days: retentionDays))
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(Palette.textPrimary)
            .frame(minHeight: 48)
            .echoRow(vertical: 0, fill: Palette.fillStrong)
            .onChange(of: retentionDays) { Task { await model.purgeExpired() } }
            if let exportURL {
                ShareLink(item: exportURL) {
                    dataRow("Export the ledger (JSON)", systemImage: "square.and.arrow.up", tint: Palette.textPrimary)
                }
                .buttonStyle(EchoPressStyle())
            }
            Menu {
                ForEach(ForgetWindow.options, id: \.self) { minutes in
                    Button("The last \(ForgetWindow.title(minutes: minutes))") { forgetMinutes = minutes }
                }
            } label: {
                dataRow("Forget the last few minutes", systemImage: "clock.arrow.circlepath", tint: Palette.rose)
            }
            if let forgotten {
                Label(forgotten, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.teal)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Button { confirmForget = true } label: {
                dataRow("Forget my day", systemImage: "trash", tint: Palette.rose)
            }
            .buttonStyle(EchoPressStyle())
            if !history.items.isEmpty {
                Button { confirmClearHistory = true } label: {
                    dataRow("Clear ask history", systemImage: "clock.arrow.circlepath", tint: Palette.rose)
                }
                .buttonStyle(EchoPressStyle())
            }
            if !ledger.entries.isEmpty {
                Button { confirmClear = true } label: {
                    dataRow("Clear the ledger", systemImage: "list.bullet.clipboard", tint: Palette.rose)
                }
                .buttonStyle(EchoPressStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }

    private func dataRow(_ title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: systemImage).font(.subheadline.weight(.semibold)).frame(width: 22)
            Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(tint)
        .frame(minHeight: 48)
        .echoRow(vertical: 0, fill: Palette.fillStrong)
        .contentShape(Rectangle())
    }
}

private struct SummaryCard: View {
    let totals: LedgerTotals
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // With very large text the three numbers stack, so none of them is cut off ("16.1…").
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.md))
                                                  : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.lg))
        VStack(alignment: .leading, spacing: Spacing.lg) {
            layout {
                stat("\(totals.stayedOnPhone)", "kept on phone", Palette.teal)
                stat("\(totals.usedMuse)", "via Muse", Palette.cloud)
                stat(ByteFormat.short(totals.bytesSent), "text sent", Palette.textPrimary)
            }
            Label {
                Text("0 bytes of audio ever leave this phone")
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.teal)
            }
                .font(.echoLabel)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 36)
                .background(Palette.teal.opacity(0.14), in: Capsule())
            Label("Passwords, codes, card and account numbers, emails and phone numbers are always swapped for placeholders on this phone before anything is sent.",
                  systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            // "4.0 KB": the number is big, the unit is tiny and sits at its bottom right.
            let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(parts.first ?? value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if parts.count > 1 {
                    Text(parts[1])
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct EntryRow: View {
    let entry: LedgerEntry
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var badge: (text: String, symbol: String, tint: Color) {
        if entry.tier == .onDevice { return ("On-device model", "cpu", Palette.local) }
        if entry.tier == .local { return ("On this phone", "iphone", Palette.local) }
        if entry.status == .pending { return ("Sending…", "paperplane", Palette.cloud) }
        if entry.isStub { return ("Stub · nothing sent", "testtube.2", Palette.amber) }
        if !entry.leftDevice { return ("Held back", "hand.raised.fill", Palette.amber) }
        if entry.status == .error { return ("Failed", "exclamationmark.triangle.fill", Palette.amber) }
        return ("Muse Spark", "cloud.fill", Palette.cloud)
    }

    var body: some View {
        let badge = badge
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(badge.text, systemImage: badge.symbol)
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(badge.tint)
                        Spacer()
                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Palette.textSecondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.textSecondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    Text(entry.query)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(entry.leftDevice && entry.bodyBytes > 0
                         ? "\(entry.snippets.count) snippets · \(ByteFormat.short(entry.bodyBytes)) sent · no audio"
                           + (entry.maskedNames > 0 ? " · \(entry.maskedNames) names masked" : "")
                           + (entry.heldBackCount > 0 ? " · \(entry.heldBackCount) private detail\(entry.heldBackCount == 1 ? "" : "s") kept here" : "")
                         : "Nothing sent")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the details")

            if expanded { details.transition(.opacity) }
        }
        .echoRow()
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !entry.reason.isEmpty {
                Text(entry.reason).font(.footnote).foregroundStyle(Palette.textSecondary)
            }
            if !entry.snippets.isEmpty {
                Text(entry.leftDevice ? "Exactly what was sent" : "What would have been sent")
                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary).textCase(.uppercase)
                if entry.maskedNames > 0 {
                    Label("\(entry.maskedNames) names were replaced with placeholders on this phone first.", systemImage: "theatermasks")
                        .font(.caption).foregroundStyle(Palette.teal)
                }
                if entry.heldBackCount > 0 {
                    Label("\(ConfidentialKind.summary(stored: entry.heldBack).prefix(1).uppercased() + ConfidentialKind.summary(stored: entry.heldBack).dropFirst()) stayed on this phone. Only placeholders were sent.", systemImage: "lock.shield.fill")
                        .font(.caption).foregroundStyle(Palette.teal)
                }
                ForEach(entry.snippets) { s in
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        Text(s.time).font(.system(.caption, design: .rounded, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Palette.cloud).frame(width: 40, alignment: .leading)
                        Text(s.text).font(.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            if entry.status == .ok, entry.leftDevice, entry.completionTokens > 0 {
                Text("\(entry.model) · \(entry.promptTokens) in / \(entry.completionTokens) out tokens · \(String(format: "%.1f", entry.latencyMs / 1000)) s")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
            }
            if entry.status == .error, !entry.error.isEmpty {
                Text(entry.error).font(.caption).foregroundStyle(Palette.amber)
            }
        }
        .padding(.top, 4)
    }
}
