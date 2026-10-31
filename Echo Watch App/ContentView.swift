import SwiftUI

/// Functional placeholder; replaced by the styled status screen in the UI step.
struct ContentView: View {
    let engine: CaptureEngine
    let link: WatchLink

    var body: some View {
        VStack(spacing: 6) {
            Text(engine.speaking ? "Speech" : "Listening").font(.headline)
            Text("captured \(engine.captured)  queued \(link.queued)  synced \(link.synced)").font(.footnote)
            Text(link.reachable ? "phone reachable" : "phone not reachable").font(.caption2)
            Button(engine.phase == .running ? "Pause" : (engine.phase == .paused ? "Resume" : "Start day")) {
                engine.phase == .idle || engine.phase == .finished ? engine.start() : engine.togglePause()
            }
        }
    }
}
