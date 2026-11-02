import SwiftUI
import WatchKit

/// The answer to "Hey Echo, …": what was asked and the answer, with a way to hear it.
struct WakeAnswerView: View {
    let reply: WatchLink.WakeReply
    let link: WatchLink

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Hey Echo", systemImage: "waveform.badge.mic")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.teal)
                if !reply.question.isEmpty {
                    Text(reply.question)
                        .font(.system(.caption2, design: .rounded, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(reply.text)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    link.wakeSpeaker.toggle(reply.text)
                } label: {
                    Label(link.wakeSpeaker.isSpeaking("answer") ? "Stop" : "Read aloud", systemImage: link.wakeSpeaker.isSpeaking("answer") ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
                Button("Done") { link.wakeSpeaker.stop(); link.wakeReply = nil }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, Spacing.sm)
        }
    }
}
