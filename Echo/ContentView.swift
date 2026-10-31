import SwiftUI

/// Functional placeholder; replaced by the styled screens in the UI step.
struct ContentView: View {
    let model: PipelineModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Echo  \(model.watchReachable ? "watch connected" : "watch not reachable")").font(.headline)
            Text(String(format: "recorded %.0fs  watch kept %.0fs  confirmed %.0fs", model.recordedSeconds, model.watchKeptSeconds, model.phoneConfirmedSeconds))
                .font(.footnote)
            Button("Reset") { Task { await model.reset() } }
            List(model.chunks.reversed()) { c in
                VStack(alignment: .leading) {
                    Text("#\(c.index) \(c.wallLabel) \(String(format: "%.1fs", c.duration)) \(c.status.rawValue)").font(.caption)
                    if let t = c.transcript { Text(t).font(.caption2) }
                }
            }
        }
        .padding()
    }
}
