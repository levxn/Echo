import Foundation
import Observation
import os
import UserNotifications
import WatchKit

/// Decides, on the watch, when to listen: it keeps the settings (and tells the phone when they change), follows `ListeningPlan` every
/// half minute, stops at the end of the hours or when the battery is low, picks listening up again after an interruption, and at the
/// start of the hours nudges the wearer, because a watch can't open its microphone without a person starting it.
@MainActor
@Observable
final class ListeningController {
    let store: ListeningStore
    private let engine: CaptureEngine
    private let link: WatchLink
    private let defaults: UserDefaults
    private let nudges = ListeningNudges()

    /// The hours have begun and nothing is listening; the main screen says so.
    private(set) var suggestListening = false
    /// A short note after the plan stopped listening ("Stopped to save battery").
    var note: String? {
        switch engine.stoppedBecause {
        case .lowBattery: "Stopped to save battery"
        case .endOfHours: "Hours are over"
        case nil: nil
        }
    }

    private static let nudgeDayKey = "echo.listenNudgeDay"
    private var loop: Task<Void, Never>?

    init(engine: CaptureEngine, link: WatchLink, store: ListeningStore? = nil, defaults: UserDefaults = .standard) {
        self.engine = engine
        self.link = link
        self.store = store ?? ListeningStore()
        self.defaults = defaults
        wire()
    }

    private func wire() {
        // What is remembered: was it listening when the app went away? (Cleared when listening ends for any reason.)
        engine.onListeningChanged = { [weak self] on in
            guard let self else { return }
            store.wasListening = on
            if on { suggestListening = false }
        }
        store.onChange = { [weak self] settings in
            self?.link.sendListening(settings)
            self?.nudges.schedule(for: settings)
        }
        link.onListenSettings = { [weak self] remote in
            guard let self, store.merge(remote) else { return }
            nudges.schedule(for: store.settings)
        }
        link.onListenCommand = { [weak self] command in self?.handle(command: command) }
        // Once the session is up, our settings go to the phone (it keeps the newer of the two).
        link.onActivated = { [weak self] in
            guard let self, store.settings.stamp > 0 else { return }
            link.sendListening(store.settings)
        }
        nudges.onStart = { [weak self] in self?.handle(command: "start") }
    }

    /// Starts following the plan. Called once, when the app opens.
    func begin() {
        guard loop == nil else { return }
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        nudges.schedule(for: store.settings)
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func handle(command: String) {
        switch command {
        case "start": if engine.phase == .idle || engine.phase == .finished { engine.begin() }
        case "stop": if engine.phase == .running { engine.togglePause() }
        default: break
        }
    }

    /// The person changed the hours on the watch.
    func set(_ settings: ListeningSettings) { store.set(settings) }

    private var battery: Double? {
        let level = WKInterfaceDevice.current().batteryLevel
        return level < 0 ? nil : Double(level)
    }

    private func todayKey(_ now: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    func tick(now: Date = Date()) {
        let nudged = defaults.string(forKey: Self.nudgeDayKey) == todayKey(now)
        switch ListeningPlan.decide(settings: store.settings, now: now, isListening: engine.phase == .running, wasListening: store.wasListening,
                                    battery: battery, nudgeSent: nudged) {
        case .none: break
        case .resume:
            Log.app.info("listening: resuming after an interruption")
            engine.begin()
        case .stop(let reason):
            Log.app.info("listening: stopping (\(String(describing: reason)))")
            engine.stop(for: reason)
        case .nudge:
            defaults.set(todayKey(now), forKey: Self.nudgeDayKey)
            suggestListening = true
            WKInterfaceDevice.current().play(.notification)
        }
    }
}

/// The daily "Start listening?" notification at the start of the hours. It is a nudge only: tapping Start opens Echo and begins.
@MainActor
final class ListeningNudges: NSObject, UNUserNotificationCenterDelegate {
    static let identifier = "echo.listen.nudge"
    static let category = "echo.listen.category"
    static let startAction = "echo.listen.start"

    var onStart: (() -> Void)?
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let start = UNNotificationAction(identifier: Self.startAction, title: "Start", options: [.foreground])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category, actions: [start], intentIdentifiers: [])])
    }

    /// One repeating notification at the start time, or none when listening is by tap only.
    func schedule(for settings: ListeningSettings) {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard settings.mode == .hours, settings.startMinute != settings.endMinute else { return }
        Task {
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Echo"
            content.body = "Time to start listening?"
            content.categoryIdentifier = Self.category
            let parts = DateComponents(hour: settings.startMinute / 60, minute: settings.startMinute % 60)
            try? await center.add(UNNotificationRequest(identifier: Self.identifier, content: content,
                                                         trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)))
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Self.identifier else { return }
        await MainActor.run { onStart?() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
