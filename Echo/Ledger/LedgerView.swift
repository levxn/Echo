import SwiftUI

/// What stayed on the phone, what left it, and the switch that controls the cloud.
struct LedgerView: View {
    let ledger: LedgerModel
    let model: PipelineModel
    /// Wipes the day (and optionally the ledger); owned by RootView because it touches every model.
    let onForget: (_ includeLedger: Bool) -> Void

    @State private var confirmClear = false
    @State private var confirmForget = false
    @State private var exportURL: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                SummaryCard(totals: ledger.totals)
                cloudSwitch
                entries
                Button { ledger.showArchitecture = true } label: {
                    Label("How Echo works", systemImage: "square.stack.3d.up.fill")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
                yourData
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .sheet(isPresented: Bindable(ledger).showArchitecture) { ArchitectureView(model: model, ledger: ledger) }
        .onChange(of: ledger.entries, initial: true) { refreshExport() }
        .confirmationDialog("Forget the day?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget the day", role: .destructive) { onForget(false) }
            Button("Forget the day and the ledger", role: .destructive) { onForget(true) }
        } message: {
            Text("Deletes every transcript, audio clip, summary and checked-off commitment on this phone. Your API key and settings stay. The ledger stays too, unless you choose to forget it.")
        }
        .confirmationDialog("Clear the privacy ledger?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear ledger", role: .destructive) { Task { await ledger.clear() } }
        } message: {
            Text("This deletes the record of what was sent. It can't be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Privacy ledger")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
            Text("Every question, and exactly what left this phone.")
                .font(.subheadline)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func refreshExport() {
        guard !ledger.entries.isEmpty else { exportURL = nil; return }
        exportURL = try? LedgerExport(entries: ledger.entries).write(into: FileManager.default.temporaryDirectory)
    }

    private var yourData: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Your data")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            Text("Everything Echo keeps is on this phone. Export the ledger, or erase what you don't want kept.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
            Image(systemName: systemImage).font(.system(size: 15, weight: .semibold)).frame(width: 22)
            Text(title).font(.system(.subheadline, design: .rounded, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, Spacing.md)
        .frame(minHeight: 48)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }

    private var cloudSwitch: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Toggle(isOn: Bindable(ledger).cloudEnabled) {
                Label("Allow Muse for synthesis questions", systemImage: "cloud.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.cloud)
            .frame(minHeight: 44)
            Text(ledger.cloudEnabled
                 ? "Questions that can't be answered by lookup are sent to Muse Spark as text. Audio never is."
                 : "Off: nothing will be sent to the cloud. Those questions show the closest moments on this phone instead.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Color.white.opacity(0.1))
            Toggle(isOn: Bindable(ledger).reviewBeforeSend) {
                Label("Review before sending", systemImage: "eye")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.cloud)
            .frame(minHeight: 44)
            Text(ledger.reviewBeforeSend
                 ? "Each request waits for you. You see the exact text first, then choose Send or Don't send."
                 : "Off: requests are sent as soon as you ask, and logged here.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider().overlay(Color.white.opacity(0.1))
            Toggle(isOn: Bindable(ledger).maskNames) {
                Label("Mask names before sending", systemImage: "theatermasks")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .tint(Palette.cloud)
            .frame(minHeight: 44)
            Text(ledger.maskNames
                 ? "People's names become placeholders like [PERSON_1] on this phone, and return in the answer. Best effort: a name the phone can't recognize is sent as spoken."
                 : "Off: names are sent as they were said.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .echoCard()
    }

    @ViewBuilder
    private var entries: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Activity")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            if ledger.entries.isEmpty {
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 28))
                        .foregroundStyle(Palette.teal)
                    Text("Nothing recorded yet")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                    Text("Ask a question and it appears here, along with whether anything left your phone.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .echoCard(padding: Spacing.xl)
            } else {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(ledger.entries) { EntryRow(entry: $0) }
                }
                .animation(.spring(duration: 0.4, bounce: 0.15), value: ledger.entries.count)
            }
        }
    }
}

private struct SummaryCard: View {
    let totals: LedgerTotals

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.lg) {
                stat("\(totals.stayedOnPhone)", "stayed on this phone", Palette.teal)
                stat("\(totals.usedMuse)", "used Muse Spark", Palette.cloud)
                stat(ByteFormat.short(totals.bytesSent), "of text sent", Palette.textPrimary)
            }
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.teal)
                Text("0 bytes of audio ever leave this phone")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .padding(.horizontal, Spacing.md)
            .frame(minHeight: 36)
            .background(Palette.teal.opacity(0.14), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    private func stat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
                withAnimation(.smooth(duration: 0.25)) { expanded.toggle() }
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
                            .font(.system(size: 11, weight: .semibold))
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
        .padding(Spacing.md)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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
