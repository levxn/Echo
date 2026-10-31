import Foundation
import NaturalLanguage
import SQLite3
import Testing
@testable import Echo

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let resources = repoRoot.appending(path: "Echo Watch App/Resources")

private func noise(_ seconds: Double, level: Double = 30, seed: UInt64 = 1) -> [Int16] {
    var rng = SeededRNG(seed: seed)
    return (0..<Int(seconds * 16_000)).map { _ in Int16(max(-32000, min(32000, Double.random(in: -1...1, using: &rng) * level * 1.7))) }
}

private func tone(_ seconds: Double, amplitude: Double = 8000, hz: Double = 220) -> [Int16] {
    (0..<Int(seconds * 16_000)).map { Int16(amplitude * sin(2 * .pi * hz * Double($0) / 16_000)) }
}

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

private func runVAD(_ samples: [Int16], config: VADConfig = VADConfig()) -> [SpeechSegment] {
    let vad = EnergyVAD(config: config)
    var out: [SpeechSegment] = []
    var i = 0
    while i + config.frameSamples <= samples.count {
        if let s = vad.push(Array(samples[i..<i + config.frameSamples])) { out.append(s) }
        i += config.frameSamples
    }
    if let s = vad.flush() { out.append(s) }
    return out
}

struct VADTests {
    @Test func silenceProducesNoSegments() {
        #expect(runVAD(noise(10)).isEmpty)
    }

    @Test func toneIsDetectedWithPreRoll() throws {
        let signal = noise(3, seed: 2) + tone(2) + noise(3, seed: 3)
        let segs = runVAD(signal)
        try #require(segs.count == 1)
        // 3.0 s onset minus 2 s pre-roll, on a 30 ms frame grid.
        #expect(abs(segs[0].startSeconds - 1.0) < 0.1)
        // pre-roll (2) + tone (2) + hangover (0.6)
        #expect(abs(segs[0].duration - 4.6) < 0.2)
        #expect(segs[0].peakDb > -25)
    }

    @Test func preRollNeverOverlapsPreviousSegment() {
        let signal = noise(3, seed: 4) + tone(1) + noise(1.2, seed: 5) + tone(1) + noise(3, seed: 6)
        let segs = runVAD(signal)
        #expect(segs.count == 2)
        if segs.count == 2 {
            #expect(segs[1].startSeconds >= segs[0].startSeconds + segs[0].duration - 0.001)
        }
    }

    @Test func shortBlipIsIgnored() {
        let signal = noise(3, seed: 7) + tone(0.06) + noise(3, seed: 8)
        #expect(runVAD(signal).isEmpty)
    }

    @Test func longSpeechIsSplitAtMaxLength() {
        let segs = runVAD(noise(2, seed: 9) + tone(70) + noise(2, seed: 10))
        #expect(segs.count >= 6)
        #expect(segs.allSatisfy { $0.duration <= 10.1 })
    }

    @Test func demoFileCoversEveryScriptedLine() throws {
        let manifest = try DemoManifest.load(from: resources.appending(path: "demo_day.json"))
        let (samples, rate) = try WAV.read(resources.appending(path: "demo_day.wav"))
        #expect(rate == 16_000)
        let segs = runVAD(samples)

        var uncovered: [String] = []
        for scene in manifest.scenes {
            for line in scene.lines {
                var covered = 0.0
                for s in segs {
                    let lo = max(line.start, s.startSeconds), hi = min(line.end, s.startSeconds + s.duration)
                    covered += max(0, hi - lo)
                }
                if covered < 0.9 * (line.end - line.start) { uncovered.append(line.text) }
            }
        }
        let kept = segs.reduce(0.0) { $0 + $1.duration }
        let noiseOnly = segs.filter { !manifest.overlapsSpeech(start: $0.startSeconds, end: $0.startSeconds + $0.duration) }
        let report = ("VAD-REPORT total=\(manifest.duration)s segments=\(segs.count) kept=\(String(format: "%.1f", kept))s noiseOnlySegments=\(noiseOnly.count) uncoveredLines=\(uncovered.count)")
        print(report)
        try? report.write(toFile: "/tmp/echo_vad_report.txt", atomically: true, encoding: .utf8)
        #expect(uncovered.isEmpty, "lines not covered: \(uncovered)")
    }
}

extension VADTests {
    /// Regression: each scene's first chunk starts in the dead air before the scene (2 s pre-roll) and
    /// used to be stamped with the previous scene's time.
    @Test func everySpeechSegmentGetsItsOwnScenesWallClock() throws {
        let manifest = try DemoManifest.load(from: resources.appending(path: "demo_day.json"))
        let clock = DemoClock(manifest: manifest)
        let (samples, _) = try WAV.read(resources.appending(path: "demo_day.wav"))
        var wrong: [String] = []
        for seg in runVAD(samples) {
            let end = seg.startSeconds + seg.duration
            // True scene = the one whose scripted lines overlap this segment the most.
            let best = manifest.scenes.enumerated().map { i, scene in
                (i, scene.lines.reduce(0.0) { $0 + max(0, min(end, $1.end) - max(seg.startSeconds, $1.start)) })
            }.max { $0.1 < $1.1 }
            guard let (i, overlap) = best, overlap > 0.5 else { continue }
            let scene = manifest.scenes[i]
            let wall = clock.wallSeconds(forOffset: seg.startSeconds)
            let low = scene.wallSeconds - 5, high = scene.wallSeconds + (scene.fileEnd - scene.fileStart) + 5
            if !(low...high).contains(wall) {
                wrong.append("segment @\(seg.startSeconds)s -> \(DemoClock.format(wall)), expected scene \(scene.label)")
            }
        }
        #expect(wrong.isEmpty, "\(wrong)")
    }
}

struct TransportTests {
    private func meta(_ i: Int) -> ChunkMeta {
        ChunkMeta(id: "id-\(i)", index: i, wallStart: 32_400 + Double(i), fileOffset: Double(i) * 3, duration: 2.5,
                  sampleRate: 16_000, peakDb: -20, meanDb: -28, sampleCount: 40_000)
    }

    @Test func bundleRoundTripsMultipleChunks() throws {
        let entries = (0..<3).map { ChunkBundle.Entry(meta: meta($0), audio: Data((0..<(1000 * ($0 + 1))).map { UInt8($0 % 251) })) }
        let encoded = try entries.map { try #require(ChunkBundle.encodeEntry($0)) }
        let data = ChunkBundle.bundle(encodedEntries: encoded, recorded: 123.5)
        let decoded = try #require(ChunkBundle.decode(data))
        #expect(decoded.entries == entries)
        #expect(decoded.recorded == 123.5)
    }

    @Test func decodeRejectsGarbageAndTruncation() throws {
        let entry = ChunkBundle.Entry(meta: meta(1), audio: Data(count: 500))
        let data = ChunkBundle.bundle(encodedEntries: [try #require(ChunkBundle.encodeEntry(entry))], recorded: 1)
        #expect(ChunkBundle.decode(Data([1, 2, 3])) == nil)
        #expect(ChunkBundle.decode(data.dropLast(10)) == nil)
        #expect(ChunkBundle.decode(data + Data([0])) == nil)
    }

    @Test func aacIsMuchSmallerThanPCMAndKeepsDuration() throws {
        let samples = tone(5)
        let aac = try #require(AudioCodec.encodeAAC(samples: samples, sampleRate: 16_000))
        #expect(aac.count < samples.pcmData.count / 3)
        let url = FileManager.default.temporaryDirectory.appending(path: "codec-test.m4a")
        try aac.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let duration = try #require(AudioCodec.duration(of: url))
        #expect(abs(duration - 5) < 0.2)
    }

    @Test func longestRealSpeechChunkFitsInOneMessage() throws {
        let (all, rate) = try WAV.read(resources.appending(path: "demo_day.wav"))
        let seconds = Int(VADConfig().maxSegmentSeconds)
        let start = 25 * rate   // inside the first scripted scene
        let samples = Array(all[start..<start + seconds * rate])
        let aac = try #require(AudioCodec.encodeAAC(samples: samples, sampleRate: rate))
        let encoded = try #require(ChunkBundle.encodeEntry(.init(meta: meta(0), audio: aac)))
        #expect(encoded.count + ChunkBundle.headerSize <= Wire.maxMessage, "encoded \(encoded.count) bytes")
    }

    @Test func samplesSurviveDataRoundTrip() {
        let samples: [Int16] = [0, 1, -1, 32767, -32768, 1234]
        #expect(samples.pcmData.int16Samples == samples)
    }

    @Test func wavRoundTrip() throws {
        let samples = tone(0.5)
        let decoded = try WAV.decode(WAV.encode(samples: samples, sampleRate: 16_000))
        #expect(decoded.samples == samples)
        #expect(decoded.sampleRate == 16_000)
    }
}

struct ClockTests {
    @Test func wallClockFollowsScenes() throws {
        let manifest = try DemoManifest.load(from: resources.appending(path: "demo_day.json"))
        let clock = DemoClock(manifest: manifest)
        let lunch = try #require(manifest.scenes.first { $0.label == "Lunch with Priya" })
        #expect(DemoClock.format(clock.wallSeconds(forOffset: lunch.fileStart)) == "12:30")
        #expect(DemoClock.format(clock.wallSeconds(forOffset: lunch.fileStart + 60)) == "12:31")
        #expect(DemoClock.format(clock.wallSeconds(forOffset: 0)).hasPrefix("09:0"))
    }
    @Test func firstChunksOfLaterScenesLandInTheirOwnScene() throws {
        let manifest = try DemoManifest.load(from: resources.appending(path: "demo_day.json"))
        let clock = DemoClock(manifest: manifest)
        // Offsets of the three chunks the Day 1 run stamped with the previous scene's time.
        for (sceneIndex, offset) in [(1, 113.2), (2, 223.3), (3, 330.1)] {
            let scene = manifest.scenes[sceneIndex]
            let wall = clock.wallSeconds(forOffset: offset)
            #expect(wall >= scene.wallSeconds - 10 && wall <= scene.wallSeconds + 5,
                    "offset \(offset) -> \(DemoClock.format(wall)), expected about \(scene.wallClock)")
        }
    }
}

struct SpikeTests {
    @Test func fts5IsAvailableInTheSimulatorSQLite() {
        var db: OpaquePointer?
        #expect(sqlite3_open(":memory:", &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        let create = sqlite3_exec(db, "CREATE VIRTUAL TABLE t USING fts5(id UNINDEXED, text, tokenize='porter unicode61')", nil, nil, nil)
        #expect(create == SQLITE_OK, "FTS5 unavailable: \(String(cString: sqlite3_errmsg(db)))")
        sqlite3_exec(db, "INSERT INTO t VALUES ('a','I have booked a plumber to come on Friday'),('b','Lisbon the second week of March')", nil, nil, nil)
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT id FROM t WHERE t MATCH 'plumbers' ORDER BY bm25(t)", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        #expect(sqlite3_step(stmt) == SQLITE_ROW, "porter stemming should match plumbers -> plumber")
    }

    @Test func wordEmbeddingsExistAndRankRelatedWordsCloser() throws {
        let embedding = try #require(NLEmbedding.wordEmbedding(for: .english))
        let vector = try #require(embedding.vector(for: "plumber"))
        let related = embedding.distance(between: "plumber", and: "repair")
        let unrelated = embedding.distance(between: "plumber", and: "march")
        let report = "dim=\(vector.count) plumber~repair=\(related) plumber~march=\(unrelated)"
        try? report.write(toFile: "/tmp/echo_spike_report.txt", atomically: true, encoding: .utf8)
        #expect(related < unrelated, "\(report)")
    }
}
