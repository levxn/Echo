import SwiftUI

@main
struct EchoWatchApp: App {
    @State private var link: WatchLink
    @State private var engine: CaptureEngine
    @State private var quickAsk: WatchAsk

    init() {
        let link = WatchLink()
        let engine = CaptureEngine(link: link)
        let quickAsk = WatchAsk(link: link)
        link.onRemoteStart = { engine.start(dayOffset: $0) }
        link.onRemoteQuickAsk = { quickAsk.run(preset: $0) }
        link.onRemoteVoiceAsk = { quickAsk.run(voice: $0) }
        _link = State(initialValue: link)
        _engine = State(initialValue: engine)
        _quickAsk = State(initialValue: quickAsk)
        // Dev hook: `-page ask` opens the Ask page directly.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-page"), i + 1 < args.count, args[i + 1] == "ask" { quickAsk.page = 1 }
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: Bindable(quickAsk).page) {
                ContentView(engine: engine, link: link).tag(0)
                AskWatchView(ask: quickAsk, link: link).tag(1)
            }
            .tabViewStyle(.verticalPage)
            .sheet(item: Bindable(link).caught) { promise in CaughtPromiseView(promise: promise, link: link) }
            .sheet(item: Bindable(link).wakeReply) { reply in WakeAnswerView(reply: reply, link: link) }
            .task {
                // Dev convenience: `simctl launch ... -autostart <token>` begins the replay without a
                // tap. The token makes it one-shot: the system may relaunch the app with the same
                // arguments, and that must not restart the replay.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-autostart"), i + 1 < args.count {
                    let token = args[i + 1]
                    if UserDefaults.standard.string(forKey: "autostartToken") != token {
                        UserDefaults.standard.set(token, forKey: "autostartToken")
                        // `-day-offset -7` replays the recording of a week ago instead of today's.
                        let offset = args.firstIndex(of: "-day-offset").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 0
                        engine.start(dayOffset: offset)
                    }
                }
                // `-quick N` runs preset N once the phone is reachable (one-shot per token, like -autostart).
                if let i = args.firstIndex(of: "-quick"), i + 2 < args.count, let n = Int(args[i + 1]) {
                    let token = args[i + 2]
                    if UserDefaults.standard.string(forKey: "quickToken") != token {
                        UserDefaults.standard.set(token, forKey: "quickToken")
                        for _ in 0..<60 where !link.reachable { try? await Task.sleep(for: .milliseconds(500)) }
                        quickAsk.run(preset: n)
                    }
                }
                // `-voice N <token>` asks recorded question N (1...5) by voice, through the real recorder, the phone and Muse.
                if let i = args.firstIndex(of: "-voice"), i + 2 < args.count, let n = Int(args[i + 1]) {
                    let token = args[i + 2]
                    if UserDefaults.standard.string(forKey: "voiceToken") != token {
                        UserDefaults.standard.set(token, forKey: "voiceToken")
                        for _ in 0..<60 where !link.reachable { try? await Task.sleep(for: .milliseconds(500)) }
                        quickAsk.run(voice: n)
                    }
                }
            }
        }
    }
}
