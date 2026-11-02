import SwiftUI

/// The Muse-written digest of the day, or the button that asks for one.
struct DigestSection: View {
    let digest: DigestModel
    let model: PipelineModel
    let player: ChunkPlayer

    var body: some View {
        switch digest.state {
        case .idle: prompt
        case .working(let plan): working(plan)
        case .ready(let ready): DigestCard(ready: ready, model: model, player: player) { run() }
        case .failed(let message): failed(message)
        case .cloudOff: notice(icon: "cloud.slash.fill", title: "Cloud is off",
                               text: "Turn it back on in the Privacy Ledger to let Muse summarize your day.")
        }
    }

    private func run() { Task { await digest.generate(chunks: model.todayChunks) } }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            EchoButton(title: "Summarize my day with Muse", systemImage: "sparkles", style: .prominent, action: run)
            Text("Sends the day's text (\(model.storedCount) snippets, no audio) to Muse Spark. It is recorded in your Privacy Ledger.")
                .font(.footnote)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func working(_ plan: TierTwoPlan) -> some View {
        HStack(spacing: Spacing.md) {
            ProgressView().tint(Palette.cloud)
            Text(digest.isStub ? "Preparing a stub preview. Nothing is sent."
                               : "Sending \(plan.snippets.count) snippets (\(ByteFormat.short(plan.bodyBytes))) to Muse Spark…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }

    private func failed(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Label("Muse couldn't summarize the day", systemImage: "exclamationmark.triangle.fill")
                .font(.echoLabel)
                .foregroundStyle(Palette.amber)
            Text(message).font(.subheadline).foregroundStyle(Palette.textPrimary)
            EchoButton(title: "Try again", systemImage: "arrow.clockwise", action: run)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }

    private func notice(icon: String, title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(title, systemImage: icon)
                .font(.echoLabel)
                .foregroundStyle(Palette.amber)
            Text(text).font(.subheadline).foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }
}

private struct DigestCard: View {
    let ready: DigestModel.Ready
    let model: PipelineModel
    let player: ChunkPlayer
    let onRerun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(spacing: Spacing.tight) {
                Label(ready.isStub ? "Stub preview · no API key" : "Muse's view of your day",
                      systemImage: ready.isStub ? "testtube.2" : "sparkles")
                    .font(.echoLabel)
                Spacer()
                ShareLink(item: ShareText.digest(summary: ready.digest.daySummary,
                                                 actions: ready.digest.actionItems.map { ($0.what, $0.toWhom, $0.due, $0.sourceTime) },
                                                 people: ready.digest.people)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel("Share the summary")
                Button(action: onRerun) {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel("Summarize again")
            }
            .foregroundStyle(ready.isStub ? Palette.amber : Palette.cloud)

            Text(ready.digest.daySummary)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !ready.digest.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader("Action items", style: .overline)
                    ForEach(ready.digest.actionItems) { item in
                        HStack(alignment: .top, spacing: Spacing.md) {
                            Image(systemName: "circle")
                                .font(.subheadline)
                                .foregroundStyle(Palette.cloud)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: Spacing.xxs) {
                                Text(item.what).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                                Text([item.toWhom, item.due].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.footnote).foregroundStyle(Palette.textSecondary)
                            }
                            Spacer(minLength: 0)
                            SourcePlayChip(label: item.sourceTime,
                                           chunk: CitationResolver.resolve(source: item.source, sourceTime: item.sourceTime,
                                                                           detail: item.what, snippets: [], chunks: model.chunks),
                                           player: player)
                        }
                        .echoRow()
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            if !ready.digest.people.isEmpty {
                FlowLayout {
                    ForEach(ready.digest.people, id: \.self) { Chip(text: $0, icon: "person.fill", tint: Palette.cloud) }
                }
            }

            Text(ready.isStub ? "Stub: nothing was sent. Run Tools/set_api_key.sh to connect Muse Spark."
                              : "\(ready.model) · Logged in your Privacy Ledger")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }
}
