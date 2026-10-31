import SwiftUI

/// What stayed on the phone, what left it, and the switch that controls the cloud.
struct LedgerView: View {
    let ledger: LedgerModel
    let model: PipelineModel

    @State private var confirmClear = false

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
                if !ledger.entries.isEmpty {
                    Button("Clear ledger", role: .destructive) { confirmClear = true }
                        .font(.footnote)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground() }
        .sheet(isPresented: Bindable(ledger).showArchitecture) { ArchitectureView(model: model, ledger: ledger) }
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
