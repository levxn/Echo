import SwiftUI

/// On the Moments tab: when Echo is off the record, and when recording is being announced.
struct PrivacyBanner: View {
    let privacy: RecordingPrivacy
    let listening: Bool

    var body: some View {
        if privacy.isOffTheRecord {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Off the record", systemImage: "eye.slash.fill")
                    .font(.echoLabel)
                    .foregroundStyle(Palette.amber)
                Text("Nothing is being kept. Say “back on the record”, or tap below, to carry on.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                EchoButton(title: "Back on the record", systemImage: "record.circle", style: .prominent, tint: Palette.teal) { privacy.resume() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .echoCard()
            .accessibilityElement(children: .contain)
        } else if privacy.announce && listening {
            Label("Recording is announced: the watch buzzes every 10 minutes while it listens.", systemImage: "applewatch.radiowaves.left.and.right")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
