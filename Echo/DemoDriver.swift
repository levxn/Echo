import Foundation
import os
import SwiftUI

/// Performs the whole demo in one continuous take so it can be recorded without relaunching the app between
/// scenes: it starts the watch, switches tabs, types each question character by character, flips the cloud
/// switch and opens the sheets, with a short caption on screen for each step.
///
/// Dev-only: it runs only with the launch argument `-demo-script`, and it uses the same code paths as the
/// buttons (the same `ask`, the same digest, the same cloud switch).
@MainActor
struct DemoDriver {
    let model: PipelineModel
    let ask: AskModel
    let ledger: LedgerModel
    let digest: DigestModel
    let voice: VoiceAskModel
    let history: AskHistoryModel
    let today: TodayState
    let player: ChunkPlayer
    let startWatch: (Int) -> Void
    /// Forgets the last N minutes, as the "Forget" button does.
    let forget: (Int) async -> Int
    /// Once the day has arrived: the person's own voice is named, and the places get their names.
    let afterSync: () async -> Void
    /// Asks the watch to run quick-ask preset N, as if tapped.
    let watchQuickAsk: (Int) -> Void
    /// Asks the watch to ask recorded question N by voice, as if its mic had been tapped.
    let watchVoiceAsk: (Int) -> Void
    let actions: ActionsModel
    let setTab: (RootTab) -> Void
    let setCaption: (String?) -> Void

    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-demo-script") }

    /// Markers the recording script reads from the log to find the sync section, which it speeds up.
    /// `notice` level, not `info`: info messages live only in a small memory buffer and some were dropped.
    private func mark(_ name: String) { Log.app.notice("demo-script: \(name)") }
    private func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    /// Shows a caption in the app and logs it with its time, so the recording script can draw it on the final video (under the
    /// phone and the watch) instead of inside the phone.
    private func caption(_ text: String?) {
        Log.app.notice("demo-script: caption: \(text ?? "-")")
        setCaption(text)
    }

    private func type(_ text: String) async {
        ask.query = ""
        for ch in text {
            ask.query.append(ch)
            try? await Task.sleep(for: .milliseconds(32))
        }
        await pause(0.6)
    }

    /// `live` marks a question that goes to Muse, so the recording script can speed up the wait for the reply.
    private func question(_ text: String, caption text2: String, hold: Double, live: Bool = false) async {
        setTab(.ask)
        caption(text2)
        await pause(0.9)
        await type(text)
        if live { mark("live-begin") }
        await ask.ask(text)
        if live { mark("live-end") }
        await pause(hold)
    }

    /// Taps the mic and lets a recorded question stand in for the voice, through the real recorder and on-device understanding.
    private func voiceQuestion(clip: Int, caption text: String, hold: Double) async {
        setTab(.ask)
        ask.clear()
        caption(text)
        await pause(0.9)
        await voice.listen(clip: clip, ask: ask)
        await pause(hold)
    }

    /// Polls `condition` until it is true or `timeout` seconds pass.
    private func wait(timeout: Double, _ condition: () -> Bool) async -> Bool {
        let started = Date()
        while Date().timeIntervalSince(started) < timeout {
            if condition() { return true }
            await pause(0.4)
        }
        return condition()
    }

    /// True once the Ask flow has finished answering `query` (locally, by Muse, or with a failure).
    private func answered(_ query: String) -> Bool {
        switch ask.state {
        case .answered(let r): r.query == query
        case .cloudAnswered(let r): r.query == query
        case .cloudFailed(let f): f.query == query
        default: false
        }
    }

    /// Plays the first citation of the current Muse answer, as a tap on its play chip would.
    private func playFirstCitation() async {
        guard case .cloudAnswered(let r) = ask.state, let item = r.answer.items.first,
              let chunk = CitationResolver.resolve(source: item.source, sourceTime: item.sourceTime, detail: item.detail + " " + item.title,
                                                   snippets: r.plan.snippets, chunks: model.chunks) else { return }
        player.toggle(chunk)
        await pause(3)
        player.stop()
    }

    /// Starts the watch and confirms it began. After the phone app relaunches, WatchConnectivity needs several
    /// seconds before the watch counts as reachable, so wait for that first, and retry if the replay doesn't start.
    private func startWatchReliably(dayOffset: Int = 0) async -> Bool {
        let day = DayID.id(offset: dayOffset, from: model.now())
        for attempt in 1...4 {
            _ = await wait(timeout: 40) { model.watchReachable }
            mark("start-watch attempt \(attempt)")
            startWatch(dayOffset)
            // The replay announces itself by starting a session for its day on the phone.
            if await wait(timeout: 15, { model.activeDayId == day && model.session == .running }) { return true }
        }
        return false
    }

    /// Waits until the watch's whole day has arrived and been processed, and has stayed that way for a while
    /// (chunks keep arriving after the watch says it is finished).
    private func waitUntilSettled(timeout: Double) async -> Bool {
        let started = Date()
        var lastCount = -1
        var stableSince: Date?
        while Date().timeIntervalSince(started) < timeout {
            let count = model.chunks.count
            if model.isSettled && count == lastCount && count > 0 {
                stableSince = stableSince ?? Date()
                if Date().timeIntervalSince(stableSince!) >= 10 { return true }
            } else {
                stableSince = nil
            }
            lastCount = count
            await pause(0.5)
        }
        return false
    }

    /// Both days from the watch. The captions change as it goes, and when the watch answers "Hey Echo" that moment is marked so the
    /// recording can play it at normal speed.
    private func sync() async -> Bool {
        caption("The watch keeps only speech and sends it to the phone")
        let history = self.history
        let ticker = Task { @MainActor in
            let started = Date()
            @MainActor func heard() -> Bool { history.items.contains { $0.via == .wakeWord } }
            while !Task.isCancelled, Date().timeIntervalSince(started) < 170, !heard() { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            if heard() {
                self.mark("wake-begin")
                self.caption("Say “Hey Echo” and the watch answers. “Off the record” keeps nothing")
                try? await Task.sleep(for: .seconds(9))
                self.mark("wake-end")
            }
            self.caption("Last week and today: checked, transcribed and indexed on the phone")
        }
        defer { ticker.cancel() }
        // Last week's recording first (kept as its own day), then today's.
        let startedPrev = await startWatchReliably(dayOffset: -7)
        let settledPrev = startedPrev ? await waitUntilSettled(timeout: 300) : false
        let started = settledPrev ? await startWatchReliably() : false
        let settled = started ? await waitUntilSettled(timeout: 300) : false
        mark(settled ? "sync-end" : (started ? "sync-timeout" : "watch-never-started"))
        return settled
    }

    func run() async {
        // The simulators can take a while to see each other after the app launches. Wait here, before the take begins, so
        // the recording script can cut that dead time out of the video.
        _ = await wait(timeout: 120) { model.watchReachable }
        mark("begin")
        setTab(.today)
        caption("Echo: a private memory for your day")
        await pause(3)

        setTab(.moments)
        mark("sync-begin")
        _ = await sync()
        await afterSync()

        setTab(.today)
        caption("\(Int((model.savedFraction * 100).rounded()))% of the day was never stored, and it all stays on the phone")
        await pause(5)

        await question("When is the plumber coming?", caption: "Lookups are answered on the phone", hold: 3)
        await question("How much was the rent increase last week?", caption: "Ask about any day: last week is remembered too", hold: 3)
        await voiceQuestion(clip: 3, caption: "Ask out loud: understood on the phone", hold: 3)

        await question("What did I promise people today?", caption: "Big questions go to Muse Spark: text only, never audio", hold: 1, live: true)
        caption("Exactly what left the phone, and 0 bytes of audio")
        ask.expandSent = true
        await pause(3.5)
        ask.expandSent = false
        ask.scrollTarget = "items"
        caption("Every claim plays the audio it came from")
        await pause(1.2)
        await playFirstCitation()
        ask.scrollTarget = nil

        setTab(.today)
        today.section = .commitments
        today.scrollTarget = "sections"
        caption("Promises are found on the phone, with no model")
        await pause(1.8)
        for promise in PromiseExtractor.extract(from: model.todayChunks).prefix(2) {
            var done = Set((UserDefaults.standard.string(forKey: DayWiper.promiseDoneKey) ?? "").split(separator: "\n").map(String.init))
            done.insert(promise.id)
            UserDefaults.standard.set(done.sorted().joined(separator: "\n"), forKey: DayWiper.promiseDoneKey)
            await pause(0.8)
        }
        await pause(1)
        setTab(.actions)
        caption("Everything you said you would do, ready to review")
        await pause(3.5)
        caption("A draft to edit: Muse writes it, passwords and numbers stay on the phone")
        if let first = actions.pending.first(where: { $0.kind == .message || $0.kind == .email }) {
            mark("live-begin")
            actions.openRequest = first.id
            _ = await wait(timeout: 40) { ledger.entries.contains { $0.kind == .draft && $0.status != .pending } }
            mark("live-end")
            await pause(3.5)
            actions.openRequest = nil
            await pause(0.8)
        }
        setTab(.today)

        today.section = .day
        today.scrollTarget = "places"
        caption("Where it happened: kept on the phone, never sent")
        await pause(4)
        today.section = .people
        today.scrollTarget = "sections"
        caption("It tells voices apart, and you can name them")
        await pause(3.5)
        today.scrollTarget = "todayTop"
        today.section = .summary

        setTab(.ledger)
        caption("Every question is on the record. Names can be masked too")
        await pause(3.5)
        caption("One switch turns the cloud off")
        await pause(1)
        ledger.cloudEnabled = false
        await pause(1.2)
        await question("Summarize my day", caption: "With the cloud off, nothing is sent", hold: 3.5)
        setTab(.ledger)
        ledger.cloudEnabled = true
        await pause(1)

        setTab(.today)
        today.section = .summary
        today.scrollTarget = "sections"
        caption("Or approve every request before it is sent")
        ledger.reviewBeforeSend = true
        await pause(1)
        let summary = Task { await digest.generate(chunks: model.todayChunks) }
        _ = await wait(timeout: 20) { ledger.gate.pending != nil }
        await pause(4)
        ledger.gate.approve()
        mark("live-begin")
        await summary.value
        mark("live-end")
        ledger.reviewBeforeSend = false
        caption("One tap: Muse summarizes the whole day")
        await pause(3)

        setTab(.ask)
        ask.clear()
        caption("From your wrist: ask out loud, the phone answers")
        await pause(1)
        let before = history.items.count
        watchVoiceAsk(5)   // "Summarize my day", spoken
        mark("live-begin")
        _ = await wait(timeout: 60) { history.items.count > before && ask.isFinishedAsking }
        mark("live-end")
        await pause(3)

        ask.clear()
        caption("Everything you ask is kept on the phone")
        ask.historyRequest = .list
        await pause(2.5)
        ask.historyRequest = .first
        await pause(2.5)
        ask.historyRequest = nil
        await pause(0.8)

        setTab(.moments)
        caption("Forget the last ten minutes, from the phone or the wrist")
        await pause(1.5)
        let gone = await forget(10)
        Log.app.notice("demo-script: forgot \(gone)")
        await pause(2.5)

        setTab(.ledger)
        ledger.focus = "yourData"
        caption("Export the ledger, or forget the day. It is all yours")
        await pause(3)
        ledger.focus = "ledgerTop"
        await pause(0.8)

        caption("How it all fits together")
        ledger.showArchitecture = true
        await pause(5)
        ledger.showArchitecture = false
        caption(nil)
        await pause(1)
        mark("finished")
    }
}

/// The caption shown during a demo take: a small glass capsule above the tab bar.
struct DemoCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(Palette.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .glassEffect(.regular, in: .rect(cornerRadius: 22))
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, 104)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
