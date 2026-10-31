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
    let startWatch: () -> Void
    let setTab: (RootTab) -> Void
    let setCaption: (String?) -> Void

    static var requested: Bool { ProcessInfo.processInfo.arguments.contains("-demo-script") }

    /// Markers the recording script reads from the log to find the sync section, which it speeds up.
    /// `notice` level, not `info`: info messages live only in a small memory buffer and some were dropped.
    private func mark(_ name: String) { Log.app.notice("demo-script: \(name)") }
    private func pause(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    private func type(_ text: String) async {
        ask.query = ""
        for ch in text {
            ask.query.append(ch)
            try? await Task.sleep(for: .milliseconds(45))
        }
        await pause(0.6)
    }

    private func question(_ text: String, caption: String, hold: Double) async {
        setTab(.ask)
        setCaption(caption)
        await pause(1.2)
        await type(text)
        await ask.ask(text)
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

    /// Starts the watch and confirms it began. After the phone app relaunches, WatchConnectivity needs several
    /// seconds before the watch counts as reachable, so wait for that first, and retry if the replay doesn't start.
    private func startWatchReliably() async -> Bool {
        for attempt in 1...4 {
            _ = await wait(timeout: 40) { model.watchReachable }
            mark("start-watch attempt \(attempt)")
            startWatch()
            // The replay announces itself by resetting the phone's day, so the session leaves "waiting".
            if await wait(timeout: 15, { model.session != .waiting || !model.chunks.isEmpty }) { return true }
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

    func run() async {
        mark("begin")
        setTab(.today)
        setCaption("Echo: a private memory for your day")
        await pause(3.5)

        setTab(.pipeline)
        setCaption("The watch keeps only speech and streams it to the phone")
        await pause(1)
        mark("sync-begin")
        let started = await startWatchReliably()
        let settled = started ? await waitUntilSettled(timeout: 300) : false
        mark(settled ? "sync-end" : (started ? "sync-timeout" : "watch-never-started"))
        setCaption("Checked, transcribed and indexed on the phone")
        await pause(2.5)

        setTab(.today)
        setCaption("\(Int((model.savedFraction * 100).rounded()))% of the day was never stored")
        await pause(5)

        await question("When is the plumber coming?", caption: "Lookups are answered on the phone", hold: 4.5)
        await question("What did Mister Brennan say about the lease?", caption: "Matching words are highlighted, and the source audio is one tap away", hold: 4)
        await question("Where is Priya going in March?", caption: "About 30 ms, and nothing left the phone", hold: 4)
        await question("What did I promise people today?", caption: "Synthesis goes to Muse Spark: text only, never audio", hold: 5)
        setCaption("Exactly the text that left the phone, and 0 bytes of audio")
        ask.expandSent = true
        await pause(6)

        setTab(.ledger)
        setCaption("Every question is on the record")
        await pause(4)
        setCaption("One switch turns the cloud off")
        await pause(1.5)
        ledger.cloudEnabled = false
        await pause(2.5)
        await question("Summarize my day", caption: "With the cloud off, nothing is sent", hold: 5)
        setTab(.ledger)
        setCaption("Switch it back on")
        await pause(1.5)
        ledger.cloudEnabled = true
        await pause(2.5)

        setTab(.today)
        setCaption("One tap: Muse summarizes the whole day")
        await pause(1.5)
        await digest.generate(chunks: model.chunks)
        await pause(6)

        setTab(.ledger)
        setCaption("How it all fits together")
        await pause(1.5)
        ledger.showArchitecture = true
        await pause(8)
        ledger.showArchitecture = false
        setCaption(nil)
        await pause(1.5)
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
