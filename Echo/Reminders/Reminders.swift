import Foundation
import Observation
import UserNotifications

/// The system's notification centre, behind a small interface so tests don't need it.
protocol NotificationScheduling: AnyObject {
    /// True if reminders may be shown. Asks the person the first time.
    func ensureAuthorized() async -> Bool
    func add(id: String, title: String, body: String, at date: Date) async throws
    func remove(ids: [String])
    /// Shows something right now with a "Remind me" button (a promise just heard, when the watch isn't there).
    func postCaught(id: String, body: String) async
    /// Told when the person taps a button on such a notification: the action and the promise id.
    func onAction(_ handler: @escaping @MainActor (String, String) -> Void)
}

extension NotificationScheduling {
    func postCaught(id: String, body: String) async {}
    func onAction(_ handler: @escaping @MainActor (String, String) -> Void) {}
}

/// Local notifications through `UNUserNotificationCenter`. Nothing leaves the phone.
final class SystemNotifications: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    /// Dev hook: `-notify-provisional` skips the permission prompt (notifications arrive quietly), for simulator checks.
    private let provisional = ProcessInfo.processInfo.arguments.contains("-notify-provisional")

    override init() {
        super.init()
        center.delegate = self
    }

    func ensureAuthorized() async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        default:
            let options: UNAuthorizationOptions = provisional ? [.alert, .sound, .provisional] : [.alert, .sound]
            return (try? await center.requestAuthorization(options: options)) ?? false
        }
    }

    func add(id: String, title: String, body: String, at date: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
    }

    func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }

    static let caughtCategory = "echo.caught"
    static let remindAction = "echo.remind"
    private var actionHandler: (@MainActor (String, String) -> Void)?

    func onAction(_ handler: @escaping @MainActor (String, String) -> Void) {
        actionHandler = handler
        let remind = UNNotificationAction(identifier: Self.remindAction, title: "Remind me", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.caughtCategory, actions: [remind], intentIdentifiers: [])])
    }

    func postCaught(id: String, body: String) async {
        guard await ensureAuthorized() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Echo · you said you would"
        content.body = body
        content.categoryIdentifier = Self.caughtCategory
        content.userInfo = ["promise": id]
        try? await center.add(UNNotificationRequest(identifier: "echo.caught.\(id)", content: content,
                                                     trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }

    /// The person tapped "Remind me" on a promise notification.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.remindAction, let id = response.notification.request.content.userInfo["promise"] as? String else { return }
        await MainActor.run { actionHandler?(response.actionIdentifier, id) }
    }

    /// A reminder that fires while Echo is open still shows.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// "Remind me" on a commitment: which ones have a reminder and when, kept on this phone. The reminder text is the
/// commitment itself, so it also appears on the lock screen; the sheet says so.
@MainActor
@Observable
final class Reminders {
    enum Problem: Equatable {
        case notAllowed
        case failed

        var message: String {
            switch self {
            case .notAllowed: "Notifications are off for Echo, so it can't remind you. Turn them on in Settings."
            case .failed: "Couldn't set that reminder. Try again."
            }
        }
    }

    static let key = "echo.reminders"
    static let prefix = "echo.promise."

    private(set) var scheduled: [String: Date] = [:]
    var problem: Problem?
    let scheduler: any NotificationScheduling
    private let defaults: UserDefaults
    private let now: () -> Date

    init(scheduler: (any NotificationScheduling)? = nil, defaults: UserDefaults = .standard, now: @escaping () -> Date = { Date() }) {
        self.scheduler = scheduler ?? SystemNotifications()
        self.defaults = defaults
        self.now = now
        load()
    }

    /// When this commitment's reminder is set for, if it has one that hasn't gone off yet.
    func date(for id: String) -> Date? { scheduled[id].flatMap { $0 > now() ? $0 : nil } }

    /// Sets (or moves) the reminder for a commitment. Asks for notification permission the first time.
    @discardableResult
    func schedule(_ promise: Promise, at date: Date) async -> Bool {
        problem = nil
        guard date > now() else { problem = .failed; return false }
        guard await scheduler.ensureAuthorized() else { problem = .notAllowed; return false }
        scheduler.remove(ids: [Self.prefix + promise.id])
        do {
            try await scheduler.add(id: Self.prefix + promise.id, title: promise.kind == .reminder ? "Echo · a reminder you heard" : "Echo · you said you would",
                                    body: promise.sentence, at: date)
        } catch {
            problem = .failed
            return false
        }
        scheduled[promise.id] = date
        save()
        return true
    }

    func cancel(_ id: String) {
        scheduler.remove(ids: [Self.prefix + id])
        scheduled[id] = nil
        save()
    }

    /// Sets (or removes) the 9 pm nudge to write the journal. It says nothing about the day.
    func setEveningJournal(enabled: Bool) async {
        scheduler.remove(ids: [JournalReminder.notificationID])
        guard enabled, let fire = JournalReminder.fireDate(now: now()), await scheduler.ensureAuthorized() else { return }
        try? await scheduler.add(id: JournalReminder.notificationID, title: "Echo", body: "Your day is ready to write up whenever you are.", at: fire)
    }

    /// Sets (or removes) the 8 am nudge to review actions. Nothing is scheduled when there is nothing to review, and it carries a count only.
    func setMorningActions(enabled: Bool, count: Int) async {
        scheduler.remove(ids: [ActionsMorning.notificationID])
        guard enabled, count > 0, let fire = ActionsMorning.fireDate(now: now()), await scheduler.ensureAuthorized() else { return }
        try? await scheduler.add(id: ActionsMorning.notificationID, title: "Echo", body: ActionsMorning.body(count: count), at: fire)
    }

    /// Moments were forgotten, so reminders about promises made in them (ids start with the moment's id) go too.
    func cancel(forChunkIDs ids: [String]) {
        let gone = Set(ids)
        for key in scheduled.keys where gone.contains(String(key.split(separator: "#").first ?? "")) { cancel(key) }
    }

    /// Forget my day: no reminder about a forgotten day should go off.
    func clearAll() {
        scheduler.remove(ids: scheduled.keys.map { Self.prefix + $0 })
        scheduled = [:]
        problem = nil
        save()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.key), let stored = try? JSONDecoder().decode([String: Double].self, from: data) else { return }
        // Reminders that have already gone off are dropped, so the list only holds what is still to come.
        scheduled = stored.mapValues { Date(timeIntervalSince1970: $0) }.filter { $0.value > now() }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(scheduled.mapValues(\.timeIntervalSince1970)), forKey: Self.key)
    }
}
