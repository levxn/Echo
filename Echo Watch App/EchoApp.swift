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
                    // Dev convenience: `simctl launch ... -autostart` begins the replay without a tap.
                    if ProcessInfo.processInfo.arguments.contains("-autostart") { engine.start() }
                }
        }
    }
}
