import Foundation
import Testing
@testable import Echo

struct WidgetSnapshotTests {
    private func promise(_ id: String, _ text: String, due: String? = nil, speaker: String = "", kind: Promise.Kind = .commitment) -> Promise {
        Promise(id: id, chunkID: id, kind: kind, timeLabel: "09:00", wallStart: 0, sentence: text, toWhom: nil, due: due, context: nil, speakerId: speaker)
    }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func theSnapshotSurvivesTheTripToTheWatchAndBack() throws {
        let snapshot = WidgetSnapshot(updated: now, openCount: 2, items: [.init(id: "a", text: "Send the spec", due: "by Friday", remindAt: now.addingTimeInterval(600))],
                                      listening: true, momentsToday: 9)
        let data = try #require(snapshot.encoded)
        #expect(WidgetSnapshot.decode(data) == snapshot)
        #expect(WidgetSnapshot.decode(Data("nonsense".utf8)) == nil)
    }

    @Test func savingAndLoadingUseTheSharedStorage() throws {
        let defaults = try #require(UserDefaults(suiteName: "echo-widget-\(UUID().uuidString)"))
        #expect(WidgetSnapshot.load(from: defaults) == .empty)
        WidgetSnapshot.sample.save(to: defaults)
        #expect(WidgetSnapshot.load(from: defaults) == WidgetSnapshot.sample)
    }

    @Test func summariesReadNaturally() {
        #expect(WidgetSnapshot.empty.summary == "Nothing open")
        var one = WidgetSnapshot.empty; one.openCount = 1
        #expect(one.summary == "1 promise open")
        one.openCount = 4
        #expect(one.summary == "4 promises open")
    }

    @Test func onlyOpenPromisesOfTheOwnVoiceAreShownAndAtMostThree() {
        let all = [promise("1", "I will send the spec.", due: "by Friday"), promise("2", "I will call Maya.", speaker: "other"),
                   promise("3", "I will pay the invoice.", speaker: "me"), promise("4", "I will book the room."), promise("5", "I will water the plants."),
                   promise("6", "Remember to buy milk.", kind: .reminder)]
        let snap = WidgetSnapshotBuilder.make(promises: all, reminders: [:], done: ["4"], myVoice: "me", momentsToday: 20, listening: false, now: now)
        #expect(snap.items.map(\.id) == ["1", "3", "5"] && snap.openCount == 3 && snap.momentsToday == 20)
        #expect(snap.items[0].text == "I will send the spec" && snap.items[0].due == "by Friday")
    }

    @Test func aReminderInThePastIsNotShownAsComingUp() {
        let all = [promise("1", "I will send the spec."), promise("2", "I will call Maya.")]
        let snap = WidgetSnapshotBuilder.make(promises: all, reminders: ["1": now.addingTimeInterval(-60), "2": now.addingTimeInterval(1800)], done: [], myVoice: nil,
                                              momentsToday: 1, listening: true, now: now)
        #expect(snap.items[0].remindAt == nil && snap.items[1].remindAt == now.addingTimeInterval(1800))
    }

    @Test func theLiveActivityIsForTheNextReminderWithinTheWindow() {
        let snap = WidgetSnapshot(updated: now, openCount: 3, items: [
            .init(id: "far", text: "Far", due: nil, remindAt: now.addingTimeInterval(20 * 3600)),
            .init(id: "later", text: "Later", due: nil, remindAt: now.addingTimeInterval(3 * 3600)),
            .init(id: "soon", text: "Soon", due: nil, remindAt: now.addingTimeInterval(900)),
            .init(id: "none", text: "None", due: nil, remindAt: nil)], listening: false, momentsToday: 0)
        let pick = WidgetSnapshotBuilder.liveCandidate(in: snap, now: now)
        #expect(pick?.text == "Soon" && pick?.due == now.addingTimeInterval(900))
        #expect(WidgetSnapshotBuilder.liveCandidate(in: .empty, now: now) == nil)
        #expect(WidgetSnapshotBuilder.liveCandidate(in: snap, within: 0.1, now: now) == nil)
    }
}
