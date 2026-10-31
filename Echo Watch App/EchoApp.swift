import SwiftUI

@main
struct EchoWatchApp: App {
    @State private var link: WatchLink
    @State private var engine: CaptureEngine

    init() {
        let link = WatchLink()
        _link = State(initialValue: link)
        _engine = State(initialValue: CaptureEngine(link: link))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(engine: engine, link: link)
                .task {
                    // Dev convenience: `simctl launch ... -autostart <token>` begins the replay without a
                    // tap. The token makes it one-shot: the system may relaunch the app with the same
                    // arguments, and that must not restart the replay.
                    let args = ProcessInfo.processInfo.arguments
                    if let i = args.firstIndex(of: "-autostart"), i + 1 < args.count {
                        let token = args[i + 1]
                        if UserDefaults.standard.string(forKey: "autostartToken") != token {
                            UserDefaults.standard.set(token, forKey: "autostartToken")
                            engine.start()
                        }
                    }
                }
        }
    }
}
