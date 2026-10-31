import SwiftUI

/// The whole system on one screen, with the real numbers from the day that was just processed.
struct ArchitectureView: View {
    let model: PipelineModel
    let ledger: LedgerModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.md) {
                header

                Stage(symbol: "applewatch", title: "Apple Watch", tint: Palette.blue, badge: "Simulated microphone") {
                    Row("Stage 1 · lenient voice detector", "Energy gate with a 2 s pre-roll so the first word is never clipped.")
                    Row("Compress and stream", "Speech only, as AAC, over WatchConnectivity.")
                    if model.recordedSeconds > 0 {
                        Stat("Kept \(Format.clock(model.watchKeptSeconds)) of \(Format.clock(model.recordedSeconds)) recorded", Palette.blue)
                    }
                }

                Connector(label: model.arrivedCount > 0 ? "\(model.arrivedCount) chunks of speech" : "chunks of speech")

                Stage(symbol: "iphone", title: "iPhone", tint: Palette.teal, badge: "Everything here runs on-device") {
                    Row("Stage 2 · speech check", "Apple SoundAnalysis rejects what isn't speech.")
                    if model.droppedCount > 0 { Stat("\(model.droppedCount) chunks dropped as non-speech", Palette.rose) }
                    Row("Transcription", "Apple's on-device speech recognition. Audio stays here.")
                    Row("Memory", "SQLite with FTS5 keyword search plus word-vector similarity.")
                    if model.storedCount > 0 { Stat("\(model.storedCount) moments indexed · \(Format.clock(model.phoneConfirmedSeconds)) confirmed", Palette.teal) }
                    Row("Router", "Plain rules decide where each question is answered.")
                }

                Connector(label: "a question")

                VStack(spacing: Spacing.sm) {
                    TierCard(symbol: "iphone", title: "Tier 0 · this phone", detail: "Lookups answered from your transcripts in about 30 ms. Nothing leaves.", tint: Palette.local, dashed: false)
                    TierCard(symbol: "cpu", title: "Tier 1 · Muse Glimmer", detail: "An open-weights model running on-device. Design only: not run in this demo.", tint: Palette.textTertiary, dashed: true)
                    TierCard(symbol: "cloud.fill", title: "Tier 2 · Muse Spark", detail: "Synthesis across the day through the Meta Model API. Text snippets only, never audio.", tint: Palette.cloud, dashed: false)
                }

                Connector(label: "every question is recorded")

                Stage(symbol: "lock.shield.fill", title: "Privacy ledger", tint: Palette.teal, badge: nil) {
                    Row("What it records", "Each question, which tier answered, the exact text and bytes sent, tokens and latency.")
                    let t = ledger.totals
                    Stat("\(t.stayedOnPhone) stayed on this phone · \(t.usedMuse) used Muse · \(ByteFormat.short(t.bytesSent)) sent", Palette.teal)
                    Row("Kill switch", "Turn the cloud off and nothing is ever sent.")
                }

                honesty
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.xxl)
        }
        .scrollIndicators(.hidden)
        .background { AuroraBackground(calm: true) }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How Echo works")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.textPrimary)
                Text("From a wrist to an answer, and what never leaves the phone.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(EchoPressStyle())
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Close")
        }
        .padding(.bottom, Spacing.sm)
    }

    private var honesty: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("What's real in this demo")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
            ForEach([
                "The audio is pre-recorded speech replayed through the real pipeline.",
                "The watch and phone are simulators linked by WatchConnectivity messages.",
                "Tier 1 is a design, not something this demo runs.",
                "Tier 2 is a live call to Muse Spark, or a labeled stub if no key is set.",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(Palette.textTertiary).padding(.top, 6)
                    Text(line).font(.footnote).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, Spacing.sm)
    }
}

// MARK: - Building blocks

private struct Stage<Content: View>: View {
    let symbol: String
    let title: String
    let tint: Color
    let badge: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
            }
            if let badge {
                Text(badge)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.14), in: Capsule())
            }
            VStack(alignment: .leading, spacing: Spacing.sm) { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }
}

private struct Row: View {
    let title: String
    let detail: String
    init(_ title: String, _ detail: String) { self.title = title; self.detail = detail }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
            Text(detail).font(.footnote).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Stat: View {
    let text: String
    let tint: Color
    init(_ text: String, _ tint: Color) { self.text = text; self.tint = tint }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

private struct TierCard: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let dashed: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textPrimary)
                Text(detail).font(.footnote).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.md)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(dashed ? 0.03 : 0.06))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(dashed ? 0.5 : 0.7), style: StrokeStyle(lineWidth: 1, dash: dashed ? [5, 4] : []))
        }
        .opacity(dashed ? 0.8 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// A short vertical link between stages, with a drifting dot unless Reduce Motion is on.
private struct Connector: View {
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Capsule().fill(Color.white.opacity(0.16)).frame(width: 2, height: 30)
                if !reduceMotion {
                    Circle()
                        .fill(Palette.teal)
                        .frame(width: 7, height: 7)
                        .shadow(color: Palette.teal.opacity(0.7), radius: 4)
                        .phaseAnimator([-12.0, 12.0]) { dot, y in dot.offset(y: y) } animation: { _ in .linear(duration: 1.0) }
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}
