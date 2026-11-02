import SwiftUI
import WatchKit

/// "Got it": a promise the wearer just made, with a way to keep a reminder for it.
struct CaughtPromiseView: View {
    let promise: WatchLink.CaughtPromise
    let link: WatchLink
    @State private var state: Keeping = .idle

    private enum Keeping { case idle, working, kept, failed }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Label("Got it", systemImage: "checkmark.circle.fill")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Palette.teal)
                Text(promise.text)
                    .font(.system(.footnote, design: .rounded, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !promise.due.isEmpty {
                    Label(promise.due, systemImage: "clock")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.teal)
                }
                switch state {
                case .kept:
                    Label("Reminder set", systemImage: "bell.badge.fill")
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                case .failed:
                    Text("Couldn't reach your phone.")
                        .font(.caption2)
                        .foregroundStyle(Palette.rose)
                default:
                    Button {
                        state = .working
                        Task {
                            let ok = await link.keep(promise: promise.id)
                            WKInterfaceDevice.current().play(ok ? .success : .failure)
                            state = ok ? .kept : .failed
                            if ok { try? await Task.sleep(for: .seconds(1.5)); link.dismissCaught() }
                        }
                    } label: {
                        Label("Keep", systemImage: "bell")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(EchoPressStyle())
                    .glassEffect(.regular.tint(Palette.teal.opacity(0.4)).interactive(), in: .capsule)
                    .disabled(state == .working)
                    Button("Dismiss") { link.dismissCaught() }
                        .font(.system(.footnote, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(.horizontal, Spacing.sm)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
    }
}
