import SwiftUI

/// When Echo listens, and a button to start or stop it now. The same switch is on the watch.
///
/// A watch can't open its microphone by itself in the background, so "All day" and "Set hours" mean: at the start time Echo asks
/// whether to listen (one tap), it stops by itself at the end, and it carries on through the hours once started.
struct ListeningCard: View {
    let model: PipelineModel
    let listening: ListeningStore
    /// The Moments tab shows the short version; the You tab shows the choices too.
    var showsChoices = true

    @State private var message: String?
    private enum Choice: Hashable { case tap, allDay, hours }

    private var settings: ListeningSettings { listening.settings }
    private var choice: Choice { settings.mode == .manual ? .tap : (settings.isAllDay ? .allDay : .hours) }

    private var state: (title: String, symbol: String, tint: Color) {
        if model.isListening { return ("Your watch is listening", "waveform", Palette.teal) }
        if model.watchReachable { return ("Your watch is ready", "applewatch", Palette.teal) }
        return ("Your watch isn't nearby", "applewatch.slash", Palette.amber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                Image(systemName: state.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(state.tint)
                    .frame(width: 36, height: 36)
                    .background(state.tint.opacity(0.16), in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(state.title).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                    Text(settings.title).font(.caption).foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            EchoButton(title: model.isListening ? "Stop listening" : "Start listening", systemImage: model.isListening ? "stop.fill" : "mic.fill",
                       style: model.isListening ? .secondary : .prominent) { toggle() }
            if let message {
                Label(message, systemImage: "info.circle")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChoices {
                EchoSegmented(segments: [.init(value: Choice.tap, title: "When I tap"), .init(value: .allDay, title: "All day"), .init(value: .hours, title: "Set hours")],
                              selection: Binding(get: { choice }, set: { choose($0) }))
                if choice == .hours { hoursPickers }
                if choice != .tap {
                    Label("At the start time Echo asks if you want to listen. One tap starts it, and it stops by itself at the end. Watches can't start the microphone on their own.",
                          systemImage: "clock.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
        .accessibilityElement(children: .contain)
    }

    private var hoursPickers: some View {
        HStack(spacing: Spacing.md) {
            DatePicker("From", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
            DatePicker("Until", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
        }
        .font(.system(.footnote, design: .rounded, weight: .semibold))
        .foregroundStyle(Palette.textPrimary)
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<ListeningSettings, Int>) -> Binding<Date> {
        Binding(get: { Calendar.current.date(byAdding: .minute, value: settings[keyPath: keyPath], to: Calendar.current.startOfDay(for: Date())) ?? Date() },
                set: { date in
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                    var next = settings
                    next[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    listening.set(next)
                })
    }

    private func choose(_ new: Choice) {
        switch new {
        case .tap: listening.set(ListeningSettings())
        case .allDay: listening.set(.allDay())
        case .hours: if choice != .hours { listening.set(ListeningSettings(mode: .hours, startMinute: 9 * 60, endMinute: 18 * 60)) }
        }
    }

    private func toggle() {
        message = nil
        let command = model.isListening ? "stop" : "start"
        if listening.sendCommand?(command) != true {
            message = "Your watch can't be reached. Open Echo on it once, then try again."
        }
    }
}
