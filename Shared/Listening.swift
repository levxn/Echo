import Foundation
import Observation

/// When Echo listens. Shared by the watch and the phone, so both show and change the same thing.
///
/// A watch can't start its microphone by itself in the background: a listening session has to be started by the person. So "set
/// hours" means: at the start time Echo nudges you (one tap starts it), it stops by itself at the end time, and once started it
/// carries on through the hours, picking itself up again if something interrupts it.
nonisolated enum ListeningMode: String, Codable, CaseIterable, Sendable {
    /// Only when the person taps Listen.
    case manual
    /// Between a start and an end time every day.
    case hours
}

nonisolated struct ListeningSettings: Codable, Equatable, Sendable {
    var mode: ListeningMode = .manual
    /// Minutes since midnight.
    var startMinute = 9 * 60
    var endMinute = 18 * 60
    /// When this was last changed (seconds since 1970). The newest change wins when the two devices disagree.
    var stamp = 0.0

    /// "All day": from morning until late evening.
    static let allDayStart = 6 * 60
    static let allDayEnd = 23 * 60
    var isAllDay: Bool { mode == .hours && startMinute == Self.allDayStart && endMinute == Self.allDayEnd }

    static func allDay(stamp: Double = 0) -> ListeningSettings { ListeningSettings(mode: .hours, startMinute: allDayStart, endMinute: allDayEnd, stamp: stamp) }

    /// Whether this time of day is inside the hours (an overnight span such as 22:00 to 06:00 works too).
    func contains(minute: Int) -> Bool {
        if startMinute == endMinute { return false }
        return startMinute < endMinute ? (minute >= startMinute && minute < endMinute) : (minute >= startMinute || minute < endMinute)
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return contains(minute: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// The next time the hours begin, after `date`.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard mode == .hours, startMinute != endMinute else { return nil }
        let day = calendar.startOfDay(for: date)
        for offset in 0...1 {
            guard let base = calendar.date(byAdding: .day, value: offset, to: day),
                  let at = calendar.date(byAdding: .minute, value: startMinute, to: base) else { continue }
            if at > date { return at }
        }
        return nil
    }

    static func clock(_ minute: Int) -> String {
        let h = (minute / 60) % 24, m = minute % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return (m == 0 ? "\(h12)" : "\(h12):" + String(format: "%02d", m)) + (h < 12 ? " am" : " pm")
    }

    /// What the mode is called on screen.
    var title: String {
        switch mode {
        case .manual: "Only when I tap"
        case .hours: isAllDay ? "All day" : "\(Self.clock(startMinute)) – \(Self.clock(endMinute))"
        }
    }

    // MARK: Wire

    static let modeKey = "mode", startKey = "start", endKey = "end", stampKey = "stamp"

    var dictionary: [String: Any] { [Self.modeKey: mode.rawValue, Self.startKey: startMinute, Self.endKey: endMinute, Self.stampKey: stamp] }
}

nonisolated extension ListeningSettings {
    init?(dictionary: [String: Any]) {
        guard let raw = dictionary[Self.modeKey] as? String, let mode = ListeningMode(rawValue: raw),
              let start = dictionary[Self.startKey] as? Int, let end = dictionary[Self.endKey] as? Int, (0..<1440).contains(start), (0..<1440).contains(end) else { return nil }
        self.init(mode: mode, startMinute: start, endMinute: end, stamp: dictionary[Self.stampKey] as? Double ?? 0)
    }
}

/// The phone's start-of-hours notification.
nonisolated enum ListeningNudge {
    static let notificationID = "echo.listen.nudge.phone"
    static let body = "Time to start listening?"
}

extension Wire {
    static let listenSettings = "listen"          // both ways (application context): the listening mode and hours
    static let listenCommand = "listen.command"   // phone -> watch: start or stop listening now
    static let commandKey = "command"             // "start" | "stop"
}

/// What the device should do right now about listening. Pure, so every case can be tested.
nonisolated enum ListeningPlan {
    enum StopReason: Equatable, Sendable { case endOfHours, lowBattery }
    enum Action: Equatable, Sendable {
        case none
        /// Listening was interrupted (the app was relaunched, a call came in) and the person hadn't stopped it: carry on.
        case resume
        case stop(StopReason)
        /// The hours have begun and nothing is listening: ask the person to start it.
        case nudge
    }

    /// Below this charge, listening stops so the watch lasts the day.
    static let lowBattery = 0.2

    static func decide(settings: ListeningSettings, now: Date, calendar: Calendar = .current, isListening: Bool, wasListening: Bool,
                       battery: Double?, nudgeSent: Bool) -> Action {
        let low = battery.map { $0 < lowBattery } ?? false
        let inHours = settings.mode == .hours && settings.contains(now, calendar: calendar)
        if isListening {
            if low { return .stop(.lowBattery) }
            if settings.mode == .hours && !inHours { return .stop(.endOfHours) }
            return .none
        }
        if wasListening && !low && (settings.mode == .manual || inHours) { return .resume }
        if inHours && !nudgeSent && !wasListening && !low { return .nudge }
        return .none
    }
}

/// The settings on this device, and whether it was listening when the app last went away.
@MainActor
@Observable
final class ListeningStore {
    static let settingsKey = "echo.listenSettings"
    static let wasListeningKey = "echo.wasListening"

    private(set) var settings: ListeningSettings
    private let defaults: UserDefaults
    private let now: () -> Date
    /// Told when the person (not the other device) changes the settings, so they can be sent across.
    var onChange: ((ListeningSettings) -> Void)?
    /// Phone only: asks the watch to start or stop now. False if the watch can't be reached.
    var sendCommand: ((String) -> Bool)?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
        if let data = defaults.data(forKey: Self.settingsKey), let stored = try? JSONDecoder().decode(ListeningSettings.self, from: data) { settings = stored } else { settings = ListeningSettings() }
    }

    var wasListening: Bool {
        get { defaults.bool(forKey: Self.wasListeningKey) }
        set { defaults.set(newValue, forKey: Self.wasListeningKey) }
    }

    /// The person changed the mode or the hours.
    func set(_ new: ListeningSettings) {
        var next = new
        next.stamp = now().timeIntervalSince1970
        guard next.mode != settings.mode || next.startMinute != settings.startMinute || next.endMinute != settings.endMinute else { return }
        settings = next
        save()
        onChange?(next)
    }

    /// The other device sent its settings: take them if they are newer. Returns whether they were taken.
    @discardableResult
    func merge(_ remote: ListeningSettings) -> Bool {
        guard remote.stamp > settings.stamp else { return false }
        settings = remote
        save()
        return true
    }

    private func save() { defaults.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey) }
}
