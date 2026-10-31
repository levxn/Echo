import Foundation

/// Ground-truth description of `demo_day.wav`, written by `Tools/make_demo_audio.py`.
nonisolated struct DemoManifest: Codable, Sendable {
    struct Line: Codable, Sendable {
        let speaker: String
        let text: String
        let start: Double
        let end: Double
    }

    struct Scene: Codable, Sendable {
        let label: String
        let wallClock: String
        let fileStart: Double
        let fileEnd: Double
        let lines: [Line]

        /// Seconds since midnight for the scene's "HH:MM" wall-clock label.
        var wallSeconds: Double {
            let parts = wallClock.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 2 else { return 0 }
            return parts[0] * 3600 + parts[1] * 60
        }
    }

    let sampleRate: Int
    let duration: Double
    let scenes: [Scene]

    static func load(from url: URL) throws -> DemoManifest {
        try JSONDecoder().decode(DemoManifest.self, from: Data(contentsOf: url))
    }

    /// True when `[start, end)` in file seconds overlaps any scripted line.
    func overlapsSpeech(start: Double, end: Double) -> Bool {
        scenes.contains { scene in
            scene.lines.contains { $0.start < end && $0.end > start }
        }
    }
}

/// Maps an offset in the demo file to a believable wall-clock time of day.
nonisolated struct DemoClock: Sendable {
    let manifest: DemoManifest

    /// Seconds since midnight. Offsets between scenes extrapolate from the preceding scene.
    func wallSeconds(forOffset offset: Double) -> Double {
        let scene = manifest.scenes.last(where: { $0.fileStart <= offset }) ?? manifest.scenes.first
        guard let scene else { return 0 }
        return scene.wallSeconds + (offset - scene.fileStart)
    }

    static func format(_ wallSeconds: Double) -> String {
        let total = Int(wallSeconds.rounded()) % 86_400
        return String(format: "%02d:%02d", total / 3600, (total % 3600) / 60)
    }
}
