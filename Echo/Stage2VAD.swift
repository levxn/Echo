import CoreMedia
import Foundation
import os
import SoundAnalysis

/// Stage-2 voice check on the phone: Apple's built-in sound classifier (on-device, no model to ship)
/// scores "speech" per analysis window. Rejects the non-speech bursts that stage 1 lets through
/// and trims each accepted chunk to the span that actually contains speech.
nonisolated enum Stage2VAD {
    struct Window: Sendable {
        let start: Double
        let end: Double
        let speech: Double
    }

    struct Result: Sendable {
        let windows: [Window]
        var maxSpeech: Double { windows.map(\.speech).max() ?? 0 }

        /// Span covered by windows at or above `threshold`, or nil if none qualify.
        func speechSpan(threshold: Double) -> ClosedRange<Double>? {
            let hits = windows.filter { $0.speech >= threshold }
            guard let first = hits.map(\.start).min(), let last = hits.map(\.end).max() else { return nil }
            return first...last
        }
    }

    private final class Collector: NSObject, SNResultsObserving {
        var windows: [Window] = []
        func request(_ request: SNRequest, didProduce result: SNResult) {
            guard let r = result as? SNClassificationResult else { return }
            let t = r.timeRange
            windows.append(Window(start: t.start.seconds, end: (t.start + t.duration).seconds,
                                  speech: r.classification(forIdentifier: "speech")?.confidence ?? 0))
        }
        func request(_ request: SNRequest, didFailWithError error: Error) {
            Log.pipe.error("sound analysis failed: \(error.localizedDescription)")
        }
        func requestDidComplete(_ request: SNRequest) {}
    }

    static func analyze(url: URL) async throws -> Result {
        let analyzer = try SNAudioFileAnalyzer(url: url)
        let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
        request.overlapFactor = 0.5
        // Prefer the shortest window the classifier allows so short chunks still yield results.
        switch request.windowDurationConstraint {
        case .enumeratedDurations(let durations):
            if let shortest = durations.min(by: { $0.seconds < $1.seconds }) { request.windowDuration = shortest }
        case .durationRange(let range):
            request.windowDuration = range.start
        @unknown default:
            break
        }
        Log.pipe.info("stage 2 window = \(request.windowDuration.seconds, format: .fixed(precision: 3))s")
        let collector = Collector()
        try analyzer.add(request, withObserver: collector)
        await analyzer.analyze()
        return Result(windows: collector.windows)
    }
}
