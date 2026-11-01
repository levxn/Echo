import SwiftUI

/// "Read aloud" under an answer; becomes "Stop" while that answer is being read.
struct ReadAloudButton: View {
    let text: String
    var id = "answer"
    @Environment(Speaker.self) private var speaker

    var body: some View {
        let speaking = speaker.speakingID == id
        Button { speaker.toggle(text, id: id) } label: {
            Label(speaking ? "Stop" : "Read aloud", systemImage: speaking ? "stop.fill" : "speaker.wave.2.fill")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Palette.teal)
                .padding(.horizontal, Spacing.lg)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(EchoPressStyle())
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityLabel(speaking ? "Stop reading" : "Read the answer aloud")
    }
}
