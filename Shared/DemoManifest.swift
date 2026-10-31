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

    /// Seconds since midnight. An offset maps to the *nearest* scene: inside a scene it is that scene,
    /// and in the dead air between scenes it extrapolates from whichever boundary is closer.
    /// (Anchoring to the preceding scene mis-stamped each scene's first chunk, because its 2 s
    /// pre-roll starts in the dead air before the scene.)
    func wallSeconds(forOffset offset: Double) -> Double {
        func distance(_ scene: DemoManifest.Scene) -> Double {
            if offset < scene.fileStart { return scene.fileStart - offset }
            if offset > scene.fileEnd { return offset - scene.fileEnd }
            return 0
        }
        guard let scene = manifest.scenes.min(by: { distance($0) < distance($1) }) else { return 0 }
        return scene.wallSeconds + (offset - scene.fileStart)
    }

    /// "HH:MM", rounded to the nearest minute (a chunk at 12:29:58 reads as 12:30).
    static func format(_ wallSeconds: Double) -> String {
        let minutes = Int((wallSeconds / 60).rounded()) % 1_440
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
