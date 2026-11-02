import SwiftUI

/// The app icon's waveform: seven bars that rise from the middle out.
struct EchoMark: View {
    var height: CGFloat = 120
    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let levels: [CGFloat] = [0.30, 0.50, 0.74, 1.0, 0.70, 0.46, 0.28]

    var body: some View {
        HStack(spacing: height * 0.07) {
            ForEach(Self.levels.indices, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: height * 0.09, height: risen ? height * Self.levels[i] : height * 0.09)
                    .shadow(color: Palette.teal.opacity(0.65), radius: height * 0.07)
                    .animation(reduceMotion ? nil : .spring(duration: 0.75, bounce: 0.35).delay(Double(abs(i - 3)) * 0.08), value: risen)
            }
        }
        .frame(height: height)
        .onAppear { risen = true }
        .accessibilityHidden(true)
    }
}

/// A brief mark on a cold launch: the waveform rises, then the app fades in. A tap skips it.
struct LaunchMark: View {
    @Binding var visible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            AuroraBackground(calm: true)
            VStack(spacing: Spacing.xl) {
                EchoMark(height: 108)
                Text("Echo")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 500 : 1300))
            dismiss()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Echo")
    }

    private func dismiss() {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { visible = false }
    }
}
