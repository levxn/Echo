import Foundation
import Testing
@testable import Echo

struct HandoffURLTests {
    @Test func mailLinkEncodesEverythingThatCouldBreakIt() throws {
        let url = try #require(HandoffURL.mailto(to: ["ravi@example.com"], subject: "Spec & plan", body: "Hi Ravi,\n\nHere it is.\nBest, Levin"))
        #expect(url.absoluteString == "mailto:ravi%40example.com?subject=Spec%20%26%20plan&body=Hi%20Ravi%2C%0A%0AHere%20it%20is.%0ABest%2C%20Levin")
        #expect(HandoffURL.mailto(to: [], subject: "", body: "")?.absoluteString == "mailto:")
    }

    @Test func aTextAndAWhatsAppMessageCarryTheNumberCleanedUp() throws {
        #expect(HandoffURL.dialable("+91 98765-43210") == "+919876543210")
        #expect(HandoffURL.dialable("(415) 555-0134") == "4155550134")
        #expect(HandoffURL.sms(to: "(415) 555-0134", body: "On my way")?.absoluteString == "sms:4155550134&body=On%20my%20way")
        #expect(HandoffURL.sms(to: nil, body: "")?.absoluteString == "sms:")
        #expect(HandoffURL.whatsApp(to: "+91 98765-43210", text: "Hi & bye")?.absoluteString == "https://wa.me/919876543210?text=Hi%20%26%20bye")
        #expect(HandoffURL.whatsApp(to: nil, text: "Hello")?.absoluteString == "https://wa.me/?text=Hello", "no number: WhatsApp asks who to send it to")
    }

    @Test func aCallNeedsARealNumber() {
        #expect(HandoffURL.tel("+1 (415) 555-0134")?.absoluteString == "tel:+14155550134")
        #expect(HandoffURL.tel("ext 5") == nil)
        #expect(HandoffPlan.call("") == .unavailable("There is no number to call yet. Add one first."))
    }

    @Test func theComposerIsUsedWhenThePhoneCanSendAndAnAddressWhenItCannot() {
        let inApp = HandoffPlan.message(channel: .email, to: "ravi@example.com", subject: "S", body: "B", canSendMail: true, canSendText: false)
        #expect(inApp == .mailComposer(to: ["ravi@example.com"], subject: "S", body: "B"))
        if case .open(let url, let app) = HandoffPlan.message(channel: .email, to: "", subject: "S", body: "B", canSendMail: false, canSendText: true) {
            #expect(app == "Mail" && url.scheme == "mailto")
        } else { Issue.record("mail without an account should fall back to a mailto: address") }
        #expect(HandoffPlan.message(channel: .messages, to: "555", subject: "", body: "Hi", canSendMail: false, canSendText: true) == .messageComposer(to: ["555"], body: "Hi"))
        if case .open(let url, let app) = HandoffPlan.message(channel: .whatsapp, to: "+1 415 555 0134", subject: "", body: "Hi", canSendMail: true, canSendText: true) {
            #expect(app == "WhatsApp" && url.host() == "wa.me")
        } else { Issue.record("WhatsApp always opens by address") }
    }
}

struct MessageTemplateTests {
    private func item(_ title: String, kind: ActionKind, person: String? = nil, due: String? = nil) -> ActionItem {
        ActionItem(id: "c#a0", kind: kind, title: title, person: person, dueText: due, quote: title, chunkID: "c", dayId: "d", wallStart: 0, timeLabel: "09:00")
    }

    @Test func anEmailForADocumentIsReadyToEditWithAPlaceholderForTheAttachment() {
        let d = MessageTemplate.draft(for: item("Send the API specification to Ravi", kind: .email, person: "Ravi", due: "by Wednesday noon"), channel: .email, userName: "Levin M S")
        #expect(d.subject == "The API specification")
        #expect(d.body.hasPrefix("Hi Ravi,"))
        #expect(d.body.contains("the API specification"))
        #expect(d.body.contains("by Wednesday noon"))
        #expect(d.body.hasSuffix("Best,\nLevin"))
        #expect(MessageTemplate.placeholders(in: d.body) == ["[Attach the file]"])
    }

    @Test func aQuickMessageIsShortAndHasNoSubjectOrSignOff() {
        let d = MessageTemplate.draft(for: item("Send the lentil soup recipe this evening", kind: .message, person: "Priya", due: "this evening"), channel: .whatsapp, userName: "Levin")
        #expect(d.subject.isEmpty)
        #expect(d.body.hasPrefix("Hi Priya,") && d.body.contains("the lentil soup recipe") && !d.body.contains("Best"))
        #expect(MessageTemplate.placeholders(in: d.body) == ["[Add the link]"] || MessageTemplate.placeholders(in: d.body).isEmpty)
    }

    @Test func aTitleIsKeptWholeAndAnUnknownPersonStillGetsAGreeting() {
        let d = MessageTemplate.draft(for: item("Give a final answer", kind: .message, person: "Mr. Brennan", due: "before November 20"), channel: .messages, userName: "Levin")
        #expect(d.body.hasPrefix("Hi Mr. Brennan,") && d.body.contains("[Your answer]"))
        #expect(MessageTemplate.draft(for: item("Send the report", kind: .email), channel: .email, userName: "L").body.hasPrefix("Hi,\n"))
        #expect(MessageTemplate.object(of: "Send the contract to Ravi") == "the contract")
    }

    @Test func aNudgeAsksWhereItStands() {
        let d = MessageTemplate.draft(for: item("Review the design document", kind: .waiting, person: "Maya", due: "on Tuesday"), channel: .whatsapp, userName: "Levin")
        #expect(d.body.hasPrefix("Hi Maya,") && d.body.contains("Just checking in on the design document") && d.body.contains("where it stands"))
        #expect(MessageTemplate.suggestedChannel(for: item("x", kind: .email)) == .email && MessageTemplate.suggestedChannel(for: item("x", kind: .message)) == .whatsapp)
    }
}

struct ContactMatcherTests {
    private let cards = [
        ContactCard(id: "1", name: "Ravi Menon", emails: ["ravi@example.com"], phones: ["+91 98765 43210"]),
        ContactCard(id: "2", name: "Ravi Shankar", emails: [], phones: []),
        ContactCard(id: "3", name: "Priya", emails: [], phones: ["555 0100"]),
        ContactCard(id: "4", name: "Brennan Cole", emails: [], phones: []),
        ContactCard(id: "5", name: "Grandma", emails: [], phones: ["555 0199"]),
    ]

    @Test func aFullNameBeatsAFirstName() {
        #expect(ContactMatcher.matches("Ravi Menon", in: cards).first?.id == "1")
        #expect(Set(ContactMatcher.matches("Ravi", in: cards).map(\.id)) == ["1", "2"], "a first name alone is ambiguous: both are offered")
    }

    @Test func titlesAndPossessivesAreIgnoredAndNothingIsInvented() {
        #expect(ContactMatcher.matches("Mr. Brennan", in: cards).map(\.id) == ["4"], "the surname matches")
        #expect(ContactMatcher.matches("Priya's", in: cards).map(\.id) == ["3"])
        #expect(ContactMatcher.matches("grandma", in: cards).map(\.id) == ["5"])
        #expect(ContactMatcher.matches("Maya", in: cards).isEmpty)
        #expect(ContactMatcher.matches("", in: cards).isEmpty && ContactMatcher.matches("Dr.", in: cards).isEmpty)
    }
}

@MainActor
private final class FakeEvents: EventWriting {
    var result: CalendarResult = .added
    var added: [EventRequest] = []
    var clashes: [String] = []
    func add(_ request: EventRequest) async -> CalendarResult { if result == .added { added.append(request) }; return result }
    func conflicts(start: Date, end: Date) async -> [String] { clashes }
}

@MainActor
private final class FakeReminderList: ReminderWriting {
    var result: CalendarResult = .added
    var calls: [(title: String, list: String?, items: [String], due: Date?)] = []
    func add(title: String, notes: String, due: Date?, hasClock: Bool, listName: String?, items: [String]) async -> CalendarResult {
        calls.append((title, listName, items, due)); return result
    }
}

@MainActor
private final class FakeContacts: ContactResolving {
    func resolve(name: String) async -> [ContactCard] { name == "Ravi" ? [ContactCard(id: "1", name: "Ravi Menon", emails: ["ravi@example.com"], phones: []) ] : [] }
}

@MainActor
private final class FakeScheduler: NotificationScheduling {
    var added: [(id: String, body: String, date: Date)] = []
    var allowed = true
    func ensureAuthorized() async -> Bool { allowed }
    func add(id: String, title: String, body: String, at date: Date) async throws { added.append((id, body, date)) }
    func remove(ids: [String]) {}
}

@MainActor
struct ActionPerformerTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func rig() async -> (performer: ActionPerformer, model: ActionsModel, events: FakeEvents, list: FakeReminderList, scheduler: FakeScheduler, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-perf-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        let model = ActionsModel(store: store)
        // one real action (id "c#a0") for the performer to mark done
        let chunk = ChunkRecord(id: "c", index: 0, wallStart: 36_000, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "c.m4a", status: .stored,
                                speechConfidence: 1, confirmedSeconds: 4, transcript: "I will send you the spec tomorrow", dayId: "2026-11-02", speakerId: "")
        await store.upsert(chunk)
        await model.refresh(chunks: [chunk], userName: "Levin", myVoice: nil, voiceNames: [:])
        let events = FakeEvents(), list = FakeReminderList(), scheduler = FakeScheduler()
        let notifier = Reminders(scheduler: scheduler, defaults: UserDefaults(suiteName: "echo-perf-\(UUID().uuidString)")!, now: { now })
        let p = ActionPerformer(model: model, events: events, reminders: list, notifier: notifier, contacts: FakeContacts(), canSendMail: { true }, canSendText: { false }, now: { now })
        return (p, model, events, list, scheduler, dir)
    }

    private func item(_ kind: ActionKind, _ title: String, due: Date? = nil) -> ActionItem {
        var i = ActionItem(id: "c#a0", kind: kind, title: title, due: due, quote: "I said \(title)", chunkID: "c", dayId: "d", wallStart: 0, timeLabel: "09:00")
        i.hasClock = due != nil
        return i
    }

    @Test func anEventIsAddedWithItsQuoteAndTheActionIsDone() async {
        let r = await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        let start = now.addingTimeInterval(86_400)
        var e = item(.calendar, "Plumber visit", due: start)
        e.durationMinutes = 60
        let outcome = await r.performer.addToCalendar(e)
        #expect(outcome == .done("Added to Calendar."))
        #expect(r.events.added.first?.title == "Plumber visit" && r.events.added.first?.minutes == 60 && r.events.added.first?.start == start)
        #expect(r.events.added.first?.notes.contains("I said Plumber visit") == true && r.events.added.first?.notes.hasSuffix("From Echo") == true)
        #expect(r.model.state(of: e.id)?.status == .done && r.model.state(of: e.id)?.handedOffVia == "Calendar")
    }

    @Test func aBirthdayRepeatsEveryYear() async {
        let r = await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        var b = item(.calendar, "Mom's birthday", due: now); b.allDay = true; b.repeatsYearly = true
        #expect(await r.performer.addToCalendar(b) == .done("Added to Calendar, every year."))
        #expect(r.events.added.first?.allDay == true && r.events.added.first?.repeatsYearly == true)
    }

    @Test func aRefusedOrFailedCalendarLeavesTheActionWhereItWasAndSaysWhy() async {
        let r = await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        let e = item(.calendar, "Standup", due: now)
        r.events.result = .denied
        #expect(await r.performer.addToCalendar(e) == .problem("Calendar access is off for Echo. Turn it on in Settings to add events."))
        r.events.result = .failed
        #expect(await r.performer.addToCalendar(e).succeeded == false)
        #expect(await r.performer.addToCalendar(item(.calendar, "No time")) == .problem("Pick a date first."))
        #expect(r.model.state(of: e.id) == nil, "nothing was done, so nothing is marked")
    }

    @Test func clashesAreReadOnlyForTimedEvents() async {
        let r = await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        r.events.clashes = ["Standup"]
        #expect(await r.performer.conflicts(for: item(.calendar, "Lunch", due: now)) == ["Standup"])
        var allDay = item(.calendar, "Birthday", due: now); allDay.allDay = true
        let allDayClashes = await r.performer.conflicts(for: allDay), todoClashes = await r.performer.conflicts(for: item(.todo, "x", due: now))
        #expect(allDayClashes.isEmpty && todoClashes.isEmpty)
    }

    @Test func aShoppingListBecomesItemsInItsOwnList() async {
        let r = await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        var s = item(.shopping, "Shopping list"); s.items = ["Eggs", "Olive oil", "Oranges"]
        #expect(await r.performer.addToReminders(s) == .done("Added 3 items to your Shopping list."))
        #expect(r.list.calls.first?.list == "Shopping" && r.list.calls.first?.items == ["Eggs", "Olive oil", "Oranges"] && r.list.calls.first?.due == nil)
        let t = item(.todo, "Order the book", due: now)
        #expect(await r.performer.addToReminders(t) == .done("Added to Reminders."))
        #expect(r.list.calls.last?.list == nil && r.list.calls.last?.due == now)
    }

    @Test func aNotificationUsesTheExistingReminderPathAndRefusesThePast() async {
        let r = await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        let when = now.addingTimeInterval(3_600)
        #expect(await r.performer.notifyMe(item(.todo, "Buy a card"), at: when).succeeded)
        #expect(r.scheduler.added.first?.date == when && r.scheduler.added.first?.body == "Buy a card")
        #expect(await r.performer.notifyMe(item(.todo, "x"), at: now.addingTimeInterval(-60)).succeeded == false)
    }

    @Test func aMessagePlanFollowsTheEditsAndHandingItOffMarksTheActionDone() async {
        let r = await rig(); defer { try? FileManager.default.removeItem(at: r.dir) }
        let m = item(.email, "Send the spec")
        var edits = ActionEdits(); edits.channel = .email; edits.to = "ravi@example.com"; edits.subject = "Spec"; edits.body = "Hi"
        #expect(r.performer.plan(for: m, edits: edits) == .mailComposer(to: ["ravi@example.com"], subject: "Spec", body: "Hi"))
        edits.channel = .messages; edits.to = "555 0100"
        if case .open(let url, _) = r.performer.plan(for: m, edits: edits) { #expect(url.scheme == "sms") } else { Issue.record("texts fall back to sms: when the phone can't send") }
        await r.performer.handedOff(m, to: "Mail")
        #expect(r.model.state(of: m.id)?.handedOffVia == "Mail")
        let ravi = await r.performer.lookUp("Ravi"), nobody = await r.performer.lookUp("Nobody")
        #expect(ravi.first?.emails == ["ravi@example.com"] && nobody.isEmpty)
    }
}
