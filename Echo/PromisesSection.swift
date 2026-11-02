import UIKit
import SwiftUI

/// Commitments heard today, found on the phone with plain rules (no model, nothing sent): a checklist with
/// who and when where known, and the source audio one tap away.
struct PromisesSection: View {
    let promises: [Promise]
    var decisions: [Decision] = []
    let model: PipelineModel
    let player: ChunkPlayer

    @Environment(Reminders.self) private var reminders
    @Environment(CalendarLink.self) private var calendar
    @Environment(VoiceBookModel.self) private var voices
    @AppStorage("echo.promiseDone") private var doneRaw = ""
    @State private var showAll = false
    @State private var onlyMine = false
    @State private var expanded: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let collapsedCount = 5
    private var done: Set<String> { Set(doneRaw.split(separator: "\n").map(String.init)) }
    /// Once the phone knows which voice is the person's, the list can be narrowed to what they said themselves.
    private var shown: [Promise] { onlyMine ? promises.filter { $0.speakerId == voices.me?.id } : promises }
    private var visible: [Promise] { Capped.visible(shown, limit: Self.collapsedCount, showAll: showAll) }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader("Commitments", meta: "\(promises.count) heard · \(promises.filter { done.contains($0.id) }.count) done")
            Label(voices.me != nil
                  ? "Found on this phone, nothing sent. Voices are told apart here, so Mine lists only what you said."
                  : "Found on this phone, nothing sent. These are commitments heard, not only yours. Say which voice is yours (People tab) to see just your own.",
                  systemImage: "lock.fill")
                .font(.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if voices.me != nil {
                EchoSegmented(segments: [.init(value: false, title: "Everyone"), .init(value: true, title: "Mine")], selection: $onlyMine)
            }

            if let problem = reminders.problem { ReminderProblem(message: problem.message, needsSettings: problem == .notAllowed) { reminders.problem = nil } }
            if let problem = calendar.problem { ReminderProblem(message: problem.message, needsSettings: problem == .notAllowed) { calendar.problem = nil } }

            VStack(spacing: Spacing.sm) {
                ForEach(visible) { promise in
                    PromiseRow(promise: promise, voice: voices.voice(id: promise.speakerId),
                               isDone: done.contains(promise.id), isExpanded: expanded == promise.id,
                               playing: player.playingID == promise.chunkID,
                               reminderAt: reminders.date(for: promise.id),
                               reminderOptions: ReminderOptions.options(due: promise.due, now: Date()),
                               calendarAt: calendar.date(for: promise.id),
                               calendarOptions: ReminderOptions.calendarOptions(due: promise.due, now: Date()),
                               onCalendar: { option in Task { if await calendar.add(promise, at: option.date) { Haptics.success() } } },
                               onRemind: { option in Task { if await reminders.schedule(promise, at: option.date) { Haptics.success() } } },
                               onCancelReminder: { reminders.cancel(promise.id) },
                               onToggleDone: { toggleDone(promise.id) },
                               onToggleExpand: { withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) { expanded = expanded == promise.id ? nil : promise.id } },
                               onPlay: { if let chunk = model.record(id: promise.chunkID) { player.toggle(chunk) } })
                }
            }
            ShowMoreButton(total: shown.count, limit: Self.collapsedCount, isExpanded: $showAll)

            if !decisions.isEmpty { DecisionsList(decisions: decisions, model: model, player: player) }
        }
        .task {
            // Dev hook: `-remind-first` sets a reminder on the first commitment, at its due time if it has one (screenshots).
            guard ProcessInfo.processInfo.arguments.contains("-remind-first"), let first = promises.first, reminders.date(for: first.id) == nil,
                  let option = ReminderOptions.options(due: first.due, now: Date()).first else { return }
            await reminders.schedule(first, at: option.date)
        }
    }

    private func toggleDone(_ id: String) {
        var set = done
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        doneRaw = set.sorted().joined(separator: "\n")
    }
}

private struct PromiseRow: View {
    let promise: Promise
    let voice: Voice?
    let isDone: Bool
    let isExpanded: Bool
    let playing: Bool
    let reminderAt: Date?
    let reminderOptions: [ReminderOption]
    let calendarAt: Date?
    let calendarOptions: [ReminderOption]
    let onCalendar: (ReminderOption) -> Void
    let onRemind: (ReminderOption) -> Void
    let onCancelReminder: () -> Void
    let onToggleDone: () -> Void
    let onToggleExpand: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Button(action: onToggleDone) {
                    Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isDone ? Palette.teal : Palette.textSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(EchoPressStyle())
                .accessibilityLabel(isDone ? "Mark as not done" : "Mark as done")

                Button(action: onToggleExpand) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(promise.sentence)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isDone ? Palette.textSecondary : Palette.textPrimary)
                            .strikethrough(isDone, color: Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        FlowLayout {
                            if let voice { Chip(text: voice.isMe ? "You" : voice.display, icon: "waveform", tint: voice.isMe ? Palette.teal : Palette.violet, size: .compact) }
                            if promise.kind == .reminder { Chip(text: "Reminder", icon: "bell.fill", tint: Palette.amber, size: .compact) }
                            if let due = promise.due { Chip(text: due, icon: "clock", tint: Palette.teal, size: .compact) }
                            if let calendarAt {
                                Chip(text: "In Calendar \(calendarAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))", icon: "calendar",
                                     tint: Palette.blue, size: .compact)
                            }
                            if let reminderAt {
                                Chip(text: "Reminder \(reminderAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))", icon: "bell.badge.fill",
                                     tint: Palette.amber, size: .compact)
                            }
                            if let to = promise.toWhom { Chip(text: "to \(to)", icon: "person.fill", tint: Palette.blue, size: .compact) }
                            Text(promise.timeLabel)
                                .font(Font.echoMeta.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, Spacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                reminderMenu
                PlayButton(isPlaying: playing, label: "Play the audio from \(promise.timeLabel)", action: onPlay)
            }
            if isExpanded, let context = promise.context {
                Text("Just before: “\(context)”")
                    .font(.footnote)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 52)
                    .transition(.opacity)
            }
        }
        .echoRow(horizontal: Spacing.sm, vertical: 0)
        .opacity(isDone ? 0.7 : 1)
    }

    /// Set, move or remove a reminder. The reminder repeats the commitment on the lock screen.
    private var reminderMenu: some View {
        Menu {
            ForEach(reminderOptions) { option in
                Button(option.title) { onRemind(option) }
            }
            if !calendarOptions.isEmpty {
                Divider()
                Section("Add to Calendar") {
                    ForEach(calendarOptions) { option in Button(option.title) { onCalendar(option) } }
                }
            }
            if reminderAt != nil {
                Divider()
                Button("Remove the reminder", role: .destructive, action: onCancelReminder)
            }
        } label: {
            Image(systemName: reminderAt == nil ? "bell" : "bell.badge.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reminderAt == nil ? Palette.textPrimary : Palette.amber)
                .frame(width: 44, height: 44)
                .background(Palette.fillStrong, in: Circle())
        }
        .accessibilityLabel(reminderAt == nil ? "Remind me" : "Change the reminder")
        .accessibilityHint("The reminder repeats this commitment, and shows on your lock screen")
    }
}

/// What was decided, in the days Echo remembers: the sentence, when it was said, and the audio.
private struct DecisionsList: View {
    let decisions: [Decision]
    let model: PipelineModel
    let player: ChunkPlayer
    @State private var showAll = false

    private static let collapsedCount = 3
    private var newestFirst: [Decision] { decisions.reversed() }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader("Decisions", meta: "\(decisions.count) made", style: .overline)
            ForEach(Capped.visible(newestFirst, limit: Self.collapsedCount, showAll: showAll)) { decision in
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.subheadline)
                        .foregroundStyle(Palette.blue)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(decision.sentence)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(decision.timeLabel)
                            .font(Font.echoMeta.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PlayButton(isPlaying: player.playingID == decision.chunkID, label: "Play the audio from \(decision.timeLabel)") {
                        if let chunk = model.record(id: decision.chunkID) { player.toggle(chunk) }
                    }
                }
                .echoRow()
                .accessibilityElement(children: .contain)
            }
            ShowMoreButton(total: decisions.count, limit: Self.collapsedCount, isExpanded: $showAll)
        }
        .padding(.top, Spacing.sm)
    }

}

/// Why a reminder or an event couldn't be set, with the way out.
private struct ReminderProblem: View {
    let message: String
    let needsSettings: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(Palette.amber)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.sm) {
                if needsSettings {
                    EchoButton(title: "Open Settings", systemImage: "gearshape.fill", style: .prominent, tint: Palette.teal) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                EchoButton(title: "Dismiss", style: .quiet, action: onDismiss)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .echoCard()
    }
}
