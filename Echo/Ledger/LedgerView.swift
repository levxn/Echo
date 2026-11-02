import SwiftUI

/// What stayed on the phone, what left it, and the switches that control the cloud.
struct LedgerView: View {
    let ledger: LedgerModel
    let model: PipelineModel
    let history: AskHistoryModel
    /// Wipes the day (and optionally the ledger); owned by RootView because it touches every model.
    let onForget: (_ includeLedger: Bool) -> Void

    @State private var confirmClear = false
    @State private var confirmForget = false
    @State private var confirmClearHistory = false
    @AppStorage(Retention.key) private var retentionDays = Retention.defaultDays
    @State private var showAllActivity = false
    @State private var exportURL: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Activity shows this many entries until "Show all" is tapped.
    static let activityLimit = 5

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                Color.clear.frame(height: 0).id("ledgerTop")
                SummaryCard(totals: ledger.totals)
                settings
                activity
                EchoButton(title: "How Echo works", systemImage: "square.stack.3d.up.fill") { ledger.showArchitecture = true }
                yourData.id("yourData")
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .task(id: ledger.focus) {
            guard let target = ledger.focus else { return }
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.7)) { proxy.scrollTo(target, anchor: .top) }
        }
        .onChange(of: ledger.entries, initial: true) { refreshExport() }
        .confirmationDialog("Forget the day?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget the day", role: .destructive) { onForget(false) }
            Button("Forget the day and the ledger", role: .destructive) { onForget(true) }
        } message: {
            Text("Deletes every transcript, audio clip, summary and checked-off commitment on this phone. Your API key and settings stay. The ledger stays too, unless you choose to forget it.")
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

    private var settings: some View {
        VStack(spacing: Spacing.md) {
            ToggleRow(title: "Allow Muse for broad questions", systemImage: "cloud.fill",
                      caption: ledger.cloudEnabled ? "Broad questions go to Muse Spark as text. Audio never does."
                                                   : "Off: nothing is sent. Broad questions show the closest moments here.",
                      isOn: Bindable(ledger).cloudEnabled)
            Divider().overlay(Palette.stroke)
            ToggleRow(title: "Review before sending", systemImage: "eye",
                      caption: ledger.reviewBeforeSend ? "You see the exact text first, then choose Send or Don't send."
                                                       : "Off: sent as soon as you ask, and logged here.",
                      isOn: Bindable(ledger).reviewBeforeSend)
            Divider().overlay(Palette.stroke)
            ToggleRow(title: "Mask names before sending", systemImage: "theatermasks",
                      caption: ledger.maskNames ? "Names become [PERSON_1] on this phone and return in the answer. Best effort."
                                                : "Off: names are sent as spoken.",
                      isOn: Bindable(ledger).maskNames)
        }
        .echoCard()
    }

    // MARK: Activity

    @ViewBuilder
    private var activity: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Activity") {
                if !ledger.entries.isEmpty {
                    Text("\(ledger.entries.count)").font(.footnote).monospacedDigit().foregroundStyle(Palette.textSecondary)
                }
            }
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
            SectionHeader("Your data")
            Text("Everything Echo keeps is on this phone. Export the ledger, or erase what you don't want kept.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.md) {
                Image(systemName: "calendar.badge.clock").font(.subheadline.weight(.semibold)).frame(width: 22)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Keep memories for").font(.system(.subheadline, design: .rounded, weight: .semibold))
                    Text("Older days are forgotten automatically.").font(.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
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

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.lg) {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(value)
                .font(.system(.title, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
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
