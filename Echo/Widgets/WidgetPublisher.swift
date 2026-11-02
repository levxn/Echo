import Foundation
import SwiftUI
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Builds the snapshot the widgets read. Pure: the app passes in what it knows.
nonisolated enum WidgetSnapshotBuilder {
    static func make(promises: [Promise], reminders: [String: Date], done: Set<String>, myVoice: String?, momentsToday: Int,
                     listening: Bool, now: Date) -> WidgetSnapshot {
        var open = promises.filter { $0.kind == .commitment && !done.contains($0.id) }
        if let myVoice { open = open.filter { $0.speakerId.isEmpty || $0.speakerId == myVoice } }
        let items = open.prefix(3).map { p in
            WidgetSnapshot.Item(id: p.id, text: p.sentence.trimmingCharacters(in: CharacterSet(charactersIn: " .!")), due: p.due,
                                remindAt: reminders[p.id].flatMap { $0 > now ? $0 : nil })
        }
        return WidgetSnapshot(updated: now, openCount: open.count, items: Array(items), listening: listening, momentsToday: momentsToday)
    }

    /// The promise whose reminder is next within `hours`, for the Live Activity.
    static func liveCandidate(in snapshot: WidgetSnapshot, within hours: Double = 8, now: Date) -> (text: String, due: Date)? {
        snapshot.items.compactMap { i -> (String, Date)? in
            guard let at = i.remindAt, at > now, at.timeIntervalSince(now) <= hours * 3600 else { return nil }
            return (i.text, at)
        }.min { $0.1 < $1.1 }.map { (text: $0.0, due: $0.1) }
    }
}

/// Keeps the Home and Lock Screen widgets, the watch complication and the Live Activity current.
@MainActor
enum WidgetPublisher {
    /// The last snapshot written, so an unchanged one doesn't reload anything.
    private static var last: WidgetSnapshot?

    static func publish(_ snapshot: WidgetSnapshot, sendToWatch: (Data) -> Void) {
        var comparable = snapshot; comparable.updated = .distantPast
        var before = last ?? .empty; before.updated = .distantPast
        guard comparable != before else { return }
        last = snapshot
        snapshot.save()
        WidgetCenter.shared.reloadAllTimelines()
        if let data = snapshot.encoded { sendToWatch(data) }
        syncLiveActivity(snapshot)
    }

    private static func syncLiveActivity(_ snapshot: WidgetSnapshot) {
        #if canImport(ActivityKit) && os(iOS)
        let candidate = WidgetSnapshotBuilder.liveCandidate(in: snapshot, now: Date())
        Task {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let running = Activity<PromiseActivityAttributes>.activities
            guard let candidate else {
                for a in running { await a.end(nil, dismissalPolicy: .immediate) }
                return
            }
            let state = PromiseActivityAttributes.ContentState(text: candidate.text, due: candidate.due)
            if let a = running.first {
                await a.update(.init(state: state, staleDate: candidate.due))
                for extra in running.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            } else {
                _ = try? Activity.request(attributes: PromiseActivityAttributes(title: "Coming up"), content: .init(state: state, staleDate: candidate.due))
            }
        }
        #endif
    }
}

/// Recomputes the widgets' snapshot whenever what it shows could have changed.
struct WidgetSync: ViewModifier {
    let model: PipelineModel
    let reminders: Reminders
    let profile: ProfileStore
    let voices: VoiceBookModel
    let link: PhoneLink
    @AppStorage(DayWiper.promiseDoneKey) private var doneRaw = ""

    private struct Key: Hashable { var chunks: Int; var stored: Int; var reminders: Int; var done: String; var listening: Bool; var me: String }

    private var key: Key {
        Key(chunks: model.todayChunks.count, stored: model.todayChunks.filter { $0.status == .stored }.count, reminders: reminders.scheduled.count,
            done: doneRaw, listening: model.session == .running, me: voices.me?.id ?? "")
    }

    func body(content: Content) -> some View {
        content.task(id: key) { await refresh() }
    }

    private func refresh() async {
        // Promises are found by rules over today's text; settle first so a burst of new moments is one update.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        let today = model.todayChunks, name = profile.name
        let found = await Task.detached(priority: .utility) { PromiseExtractor.extract(from: today, userName: name) }.value
        let done = Set(doneRaw.split(separator: "\n").map(String.init))
        let snapshot = WidgetSnapshotBuilder.make(promises: found, reminders: reminders.scheduled, done: done, myVoice: voices.me?.id,
                                                  momentsToday: today.count, listening: model.session == .running, now: Date())
        WidgetPublisher.publish(snapshot) { link.sendWidget($0) }
    }
}
