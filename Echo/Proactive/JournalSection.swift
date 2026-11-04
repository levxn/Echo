import SwiftUI
import UIKit

/// "Write tonight's entry": a private journal entry for the day, written by Muse when you ask, kept on this phone.
struct JournalSection: View {
    let journal: JournalModel
    let model: PipelineModel
    @Environment(LedgerModel.self) private var ledger
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Color.clear.frame(height: 0).task {
                if Self.autoRun, case .idle = journal.state { await journal.generate(chunks: model.todayChunks) }
            }
            switch journal.state {
            case .idle:
                prompt
            case .working(let plan):
                HStack(spacing: Spacing.md) {
                    ProgressView().tint(Palette.cloud)
                    Text(journal.isStub ? "Preparing a stub preview. Nothing is sent."
                                        : "Sending \(plan.snippets.count) snippets (\(ByteFormat.short(plan.bodyBytes))) to Muse Spark…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()
            case .ready(let ready):
                entry(ready, today: true)
            case .failed(let message):
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Label("Muse couldn't write the entry", systemImage: "exclamationmark.triangle.fill").font(.echoLabel).foregroundStyle(Palette.amber)
                    Text(message).font(.subheadline).foregroundStyle(Palette.textPrimary)
                    EchoButton(title: "Try again", systemImage: "arrow.clockwise") { write() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .echoCard()
            case .cloudOff:
                Label("Cloud is off, so Muse can't write your entry. Turn it back on in the You tab.", systemImage: "cloud.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(Palette.amber)
            }
            ForEach(journal.earlier.prefix(3), id: \.day) { entry($0, today: false) }
        }
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EchoButton(title: "Write tonight's entry with Muse", systemImage: "book.closed.fill", action: write)
            Text("A private journal entry for the day, in your voice. It is only written when you ask, and the text is logged in your Privacy Ledger.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func write() { Task { await journal.generate(chunks: model.todayChunks) } }

    // (`-journal-run` writes the entry as soon as Today's summary shows, for screenshots.)
    private static let autoRun = ProcessInfo.processInfo.arguments.contains("-journal-run")

    private func entry(_ ready: JournalModel.Ready, today: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack {
                Label(today ? "Tonight's entry" : DayID.longLabel(ready.day), systemImage: "book.closed.fill")
                    .font(.echoLabel)
                    .foregroundStyle(ready.isStub ? Palette.amber : Palette.cloud)
                Spacer()
                if today {
                    Button(action: write) {
                        Image(systemName: "arrow.clockwise").font(.footnote.weight(.semibold)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(EchoPressStyle())
                    .accessibilityLabel("Write it again")
                }
            }
            Text(ready.entry.title)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(ready.entry.entry)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !ready.entry.highlights.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(ready.entry.highlights, id: \.self) { line in
                        Label(line, systemImage: "sparkle").font(.footnote).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            FlowLayout {
                Button {
                    UIPasteboard.general.string = ready.entry.text
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                        .padding(.horizontal, Spacing.lg)
                        .frame(minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
                ShareAnswerButton(text: ready.entry.text)
            }
            Text(ready.isStub ? "Stub: nothing was sent. Run Tools/set_api_key.sh to connect Muse Spark." : "\(ready.model) · Kept on this phone")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }
}
