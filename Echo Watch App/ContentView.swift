import SwiftUI
import WatchKit

/// The watch's main screen: one big button to listen, one line saying what it is doing, and when it listens. Everything technical
/// (what was heard, queued, synced) lives on the More page.
struct ContentView: View {
    let engine: CaptureEngine
    let link: WatchLink
    let listening: ListeningController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showHours = false

    private var isOn: Bool { engine.phase == .running }

    /// One plain line under the button.
    private var status: (text: String, tint: Color) {
        if let problem = engine.problem, engine.phase == .idle { return (problem, Palette.amber) }
        if let note = listening.note, !isOn { return (note, Palette.amber) }
        if listening.suggestListening && !isOn { return ("Time to listen", Palette.teal) }
        switch engine.phase {
        case .idle: return ("Tap to listen", Palette.textSecondary)
        case .running: return (engine.isLive ? "Listening" : "Playing the day", Palette.teal)
        case .paused: return ("Paused", Palette.textSecondary)
        case .finished: return (engine.wasLive ? "Tap to listen again" : "Day captured", Palette.textSecondary)
        }
    }

    private var ringTint: Color {
        switch engine.phase {
        case .paused: Palette.textTertiary
        case .idle, .finished: Palette.blue
        case .running: engine.speaking ? Palette.teal : Palette.blue
        }
    }

    var body: some View {
        ZStack {
            AuroraBackground(calm: true, fps: 12)
            VStack(spacing: Spacing.sm) {
                Button(action: primaryAction) {
                    ListenRing(level: engine.level, tint: ringTint, active: isOn, reduceMotion: reduceMotion)
                        .frame(width: 104, height: 104)
                        .contentShape(Circle())
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel(isOn ? "Stop listening" : "Start listening")

                Text(status.text)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button { showHours = true } label: {
                    Label(listening.store.settings.title, systemImage: "clock")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, Spacing.md)
                        .frame(minHeight: 32)
                }
                .buttonStyle(EchoPressStyle())
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityLabel("When to listen: \(listening.store.settings.title)")
            }
            .overlay(alignment: .topLeading) { linkDot }
        }
        .sheet(isPresented: $showHours) { ListeningSheet(listening: listening) }
    }

    /// Whether the phone is near: a dot, and a line only when it isn't.
    private var linkDot: some View {
        Circle()
            .fill(link.reachable ? Palette.teal : Palette.amber)
            .frame(width: 7, height: 7)
            .padding(.leading, Spacing.xs)
            .accessibilityLabel(link.reachable ? "Phone connected" : "Phone not nearby. Echo keeps what it hears until it is.")
    }

    private func primaryAction() {
        WKInterfaceDevice.current().play(isOn ? .stop : .start)
        switch engine.phase {
        case .idle, .finished: engine.begin()
        case .running, .paused: engine.togglePause()
        }
    }
}

/// The big round button: it breathes with the microphone while listening.
private struct ListenRing: View {
    let level: Double
    let tint: Color
    let active: Bool
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.6), tint.opacity(0)], center: .center, startRadius: 6, endRadius: 60))
                .scaleEffect(active && !reduceMotion ? 0.85 + level * 0.4 : 0.9)
                .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0.3), value: level)
            Circle().stroke(active ? tint.opacity(0.9) : Palette.stroke, lineWidth: 5)
                .padding(8)
            Image(systemName: active ? "waveform" : "mic.fill")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
                .symbolEffect(.variableColor.iterative, isActive: active && !reduceMotion)
        }
        .accessibilityHidden(true)
    }
}

/// Choose when Echo listens: only when you tap, all day, or between two times.
struct ListeningSheet: View {
    let listening: ListeningController
    @Environment(\.dismiss) private var dismiss

    private var settings: ListeningSettings { listening.store.settings }
    private enum Choice { case tap, allDay, hours }
    private var choice: Choice { settings.mode == .manual ? .tap : (settings.isAllDay ? .allDay : .hours) }

    var body: some View {
        NavigationStack {
            List {
                row("Only when I tap", selected: choice == .tap) { listening.set(ListeningSettings()) }
                row("All day", selected: choice == .allDay) { listening.set(.allDay()) }
                row("Set hours", selected: choice == .hours) {
                    if choice != .hours { listening.set(ListeningSettings(mode: .hours, startMinute: 9 * 60, endMinute: 18 * 60)) }
                }
                if choice == .hours {
                    Picker("From", selection: hour(\.startMinute)) { ForEach(0..<24, id: \.self) { Text(ListeningSettings.clock($0 * 60)).tag($0) } }
                    Picker("Until", selection: hour(\.endMinute)) { ForEach(0..<24, id: \.self) { Text(ListeningSettings.clock($0 * 60)).tag($0) } }
                }
                if choice != .tap {
                    Text("At the start time Echo asks if you want to listen. One tap starts it, and it stops by itself at the end.")
                        .font(.caption2)
                        .foregroundStyle(Palette.textSecondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Listen")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func row(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(.footnote, design: .rounded, weight: .semibold))
                Spacer()
                if selected { Image(systemName: "checkmark").foregroundStyle(Palette.teal) }
            }
        }
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    private func hour(_ keyPath: WritableKeyPath<ListeningSettings, Int>) -> Binding<Int> {
        Binding(get: { settings[keyPath: keyPath] / 60 },
                set: { var s = settings; s[keyPath: keyPath] = $0 * 60; listening.set(s) })
    }
}

/// The page past Ask: forgetting what was just heard, and the numbers behind the scenes (kept out of the way on purpose).
struct MoreView: View {
    let engine: CaptureEngine
    let link: WatchLink

    @State private var confirmForget = false
    @State private var forgotten: String?
    @State private var showDetails = false

    var body: some View {
        ZStack {
            AuroraBackground(calm: true, fps: 12)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("More")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Button { confirmForget = true } label: {
                        Label(forgotten ?? "Forget the last 10 min", systemImage: forgotten == nil ? "clock.arrow.circlepath" : "checkmark.circle.fill")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(forgotten == nil ? Palette.textPrimary : Palette.teal)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(EchoPressStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .disabled(!link.reachable)
                    .accessibilityHint("Deletes what was heard in the last 10 minutes, on your phone")

                    Button { withAnimation { showDetails.toggle() } } label: {
                        HStack {
                            Text("Behind the scenes").font(.system(.footnote, design: .rounded, weight: .semibold))
                            Spacer()
                            Image(systemName: showDetails ? "chevron.up" : "chevron.down").font(.caption2)
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if showDetails {
                        Counter(value: engine.captured, label: "heard")
                        Counter(value: link.queued, label: "waiting to send")
                        Counter(value: link.synced, label: "sent to phone")
                        Text(link.reachable ? "Phone connected" : "Phone not nearby. Echo keeps what it hears until it is.")
                            .font(.caption2)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }
        }
        .confirmationDialog("Forget the last 10 minutes?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Forget", role: .destructive) {
                Task {
                    let count = await link.forget(minutes: 10)
                    WKInterfaceDevice.current().play(count == nil ? .failure : .success)
                    forgotten = count.map { $0 == 0 ? "Nothing to forget" : "Forgot \($0)" } ?? "Phone not reachable"
                    try? await Task.sleep(for: .seconds(4))
                    forgotten = nil
                }
            }
        } message: {
            Text("Deletes it from your phone.")
        }
    }
}

private struct Counter: View {
    let value: Int
    let label: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            Text("\(value)")
                .font(.system(.callout, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: value)
                .frame(minWidth: 30, alignment: .trailing)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.tight)
        .padding(.vertical, Spacing.xs)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
