import Foundation
import Observation

/// Does what an action asks, after the person has reviewed it: puts the event in the calendar, the to-do in Reminders, a reminder
/// notification on the phone, or works out which app a message opens in. Each success marks the action done and says how.
/// Everything stays on the phone.
@MainActor
@Observable
final class ActionPerformer {
    enum Outcome: Equatable {
        case done(String)
        case problem(String)
        var message: String { switch self { case .done(let m), .problem(let m): m } }
        var succeeded: Bool { if case .done = self { true } else { false } }
    }

    private let model: ActionsModel
    private let events: any EventWriting
    private let reminderList: any ReminderWriting
    private let notifier: Reminders
    let contacts: any ContactResolving
    private let canSendMail: () -> Bool
    private let canSendText: () -> Bool
    private let now: () -> Date
    private let calendar: Calendar

    init(model: ActionsModel, events: any EventWriting, reminders: any ReminderWriting, notifier: Reminders, contacts: any ContactResolving,
         canSendMail: @escaping () -> Bool = { false }, canSendText: @escaping () -> Bool = { false },
         now: @escaping () -> Date = { Date() }, calendar: Calendar = .current) {
        self.model = model
        self.events = events
        self.reminderList = reminders
        self.notifier = notifier
        self.contacts = contacts
        self.canSendMail = canSendMail
        self.canSendText = canSendText
        self.now = now
        self.calendar = calendar
    }

    static let shoppingList = "Shopping"

    // MARK: Calendar

    /// The end of the event, for the clash check.
    private func end(of item: ActionItem, start: Date) -> Date {
        item.allDay ? (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: start)) ?? start) : start.addingTimeInterval(Double(item.durationMinutes) * 60)
    }

    /// What already sits in the calendar at that time (nothing if the calendar can't be read).
    func conflicts(for item: ActionItem) async -> [String] {
        guard item.kind == .calendar, !item.allDay, let start = item.due else { return [] }
        return await events.conflicts(start: start, end: end(of: item, start: start))
    }

    func addToCalendar(_ item: ActionItem) async -> Outcome {
        guard let start = item.due else { return .problem("Pick a date first.") }
        var notes = item.quote.isEmpty ? "" : "“\(item.quote)”\n\n"
        notes += "From Echo"
        let result = await events.add(EventRequest(title: item.title, notes: notes, start: start, minutes: item.durationMinutes,
                                                   allDay: item.allDay, repeatsYearly: item.repeatsYearly))
        switch result {
        case .added:
            await model.markDone(item.id, via: "Calendar")
            return .done(item.repeatsYearly ? "Added to Calendar, every year." : "Added to Calendar.")
        case .denied: return .problem("Calendar access is off for Echo. Turn it on in Settings to add events.")
        case .failed: return .problem("Couldn't add that to your calendar. Try again.")
        }
    }

    // MARK: Reminders and notifications

    /// To-dos go to the Reminders app; a shopping list goes there as a list of items.
    func addToReminders(_ item: ActionItem) async -> Outcome {
        let shopping = item.kind == .shopping && !item.items.isEmpty
        let result = await reminderList.add(title: item.title, notes: item.quote.isEmpty ? "From Echo" : "“\(item.quote)”\n\nFrom Echo", due: shopping ? nil : item.due,
                                            hasClock: item.hasClock, listName: shopping ? Self.shoppingList : nil, items: shopping ? item.items : [])
        switch result {
        case .added:
            await model.markDone(item.id, via: "Reminders")
            return .done(shopping ? "Added \(item.items.count) items to your \(Self.shoppingList) list." : "Added to Reminders.")
        case .denied: return .problem("Reminders access is off for Echo. Turn it on in Settings.")
        case .failed: return .problem("Couldn't add that to Reminders. Try again.")
        }
    }

    /// A notification from Echo itself at a time the person picks ("Remind me later", "Remind me to check").
    func notifyMe(_ item: ActionItem, at date: Date) async -> Outcome {
        guard await notifier.schedule(item.asPromise, at: date) else { return .problem(notifier.problem?.message ?? "Couldn't set that reminder.") }
        return .done("Reminder set for \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute())).")
    }

    // MARK: Messages and calls

    /// Which app a message opens in, from the person's edits.
    func plan(for item: ActionItem, edits: ActionEdits) -> HandoffPlan {
        HandoffPlan.message(channel: edits.channel ?? MessageTemplate.suggestedChannel(for: item), to: edits.to ?? "", subject: edits.subject ?? "",
                            body: edits.body ?? "", canSendMail: canSendMail(), canSendText: canSendText())
    }

    /// Called once the system composer or the other app has been opened: the action is done, and the card says where it went.
    func handedOff(_ item: ActionItem, to app: String) async {
        await model.markDone(item.id, via: app)
    }

    // MARK: People

    /// The contacts that could be this person (empty if there is no permission). Looked up on the phone only.
    func lookUp(_ name: String) async -> [ContactCard] { await contacts.resolve(name: name) }
}
