import Foundation
import Testing
@testable import Echo

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private let office = Coordinate(lat: 12.9716, lon: 77.5946)
private let cafe = Coordinate(lat: 12.9352, lon: 77.6245)
private let home = Coordinate(lat: 12.9784, lon: 77.6408)

private func heard(_ id: String, _ text: String, at spot: Coordinate?, wall: Double = 100, day: String = DayID.today(), status: ChunkStatus = .stored) -> ChunkRecord {
    ChunkRecord(id: id, index: 0, wallStart: wall, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "\(id).m4a",
                status: status, speechConfidence: 1, confirmedSeconds: 4, transcript: text, dayId: day, coordinate: spot)
}

struct CoordinateTests {
    @Test func distancesAreInMetres() {
        #expect(office.distance(to: office) == 0)
        let d = office.distance(to: cafe)
        #expect(d > 5_000 && d < 5_400, "about 5.2 km: \(d)")
        #expect(abs(Coordinate(lat: 0, lon: 0).distance(to: Coordinate(lat: 0, lon: 1)) - 111_195) < 300)
    }

    @Test func roundingIsToAboutAHundredMetres() {
        let c = Coordinate(lat: 12.971634, lon: 77.594612).coarse()
        #expect(c == Coordinate(lat: 12.972, lon: 77.595))
        #expect(Coordinate(lat: 12.971634, lon: 77.594612).distance(to: c) < 100)
    }

    @Test func aMomentsPlaceTravelsWithTheChunkOverTheWire() throws {
        let meta = ChunkMeta(id: "a", index: 1, wallStart: 10, fileOffset: 2, duration: 3, sampleRate: 16_000, peakDb: -3, meanDb: -20, sampleCount: 100,
                             coordinate: office.coarse())
        let entry = try #require(ChunkBundle.encodeEntry(.init(meta: meta, audio: Data([1, 2, 3]))))
        let bundle = ChunkBundle.bundle(encodedEntries: [entry], recorded: 5)
        let back = try #require(ChunkBundle.decode(bundle)).entries.first
        #expect(back?.meta.coordinate == office.coarse())
        let without = ChunkMeta(id: "b", index: 0, wallStart: 0, fileOffset: 0, duration: 1, sampleRate: 16_000, peakDb: 0, meanDb: 0, sampleCount: 1)
        let oldEntry = try #require(ChunkBundle.encodeEntry(.init(meta: without, audio: Data())))
        let old = try #require(ChunkBundle.decode(ChunkBundle.bundle(encodedEntries: [oldEntry], recorded: 1)))
        #expect(old.entries.first?.meta.coordinate == nil, "a watch that doesn't know where it is sends nothing")
    }

    @Test func theRecordedDaysScenesSayWhereTheyHappened() throws {
        for stem in ["demo_day", "demo_day_prev"] {
            let m = try DemoManifest.load(from: repoRoot.appending(path: "Echo Watch App/Resources/\(stem).json"))
            #expect(m.scenes.allSatisfy { $0.place != nil }, "\(stem)")
            let first = try #require(m.scenes.first)
            #expect(m.place(atOffset: first.fileStart + 1) == first.place)
            #expect(m.place(atOffset: first.fileStart - 50) == first.place, "dead air before the first scene is still that scene's place")
        }
    }
}

struct PlaceLogicTests {
    @Test func aSpotIsInTheNearestNamedPlaceItIsWithinReachOf() {
        let a = Place(id: "a", name: "Office", coordinate: office), b = Place(id: "b", name: "Home", coordinate: home)
        #expect(PlaceLogic.place(for: Coordinate(lat: 12.9718, lon: 77.5948), in: [a, b])?.name == "Office")
        #expect(PlaceLogic.place(for: cafe, in: [a, b]) == nil && PlaceLogic.place(for: nil, in: [a, b]) == nil)
        let wide = Place(id: "w", name: "Campus", coordinate: office, radius: 6_000)
        #expect(PlaceLogic.place(for: cafe, in: [wide])?.name == "Campus")
    }

    @Test func momentsGatherIntoPlacesMostHeardFirstAndNamedOnesKeepTheirName() {
        let chunks = [heard("a", "x", at: office), heard("b", "x", at: office.coarse()), heard("c", "x", at: cafe), heard("d", "x", at: home),
                      heard("e", "x", at: home), heard("f", "x", at: home), heard("none", "x", at: nil), heard("dropped", "x", at: home, status: .dropped)]
        let unnamed = PlaceLogic.clusters(from: chunks, places: [])
        #expect(unnamed.map(\.count) == [3, 2, 1] && unnamed.allSatisfy { $0.place == nil } && unnamed[0].title == "Unnamed place")
        let named = PlaceLogic.clusters(from: chunks, places: [Place(id: "h", name: "Home", coordinate: home)])
        #expect(named.first?.title == "Home" && named.first?.momentIDs.sorted() == ["d", "e", "f"] && named.count == 3)
    }

    @Test func nearbySpotsAreOnePlaceFarOnesAreNot() {
        let near = Coordinate(lat: office.lat + 0.0008, lon: office.lon)   // about 90 m
        let far = Coordinate(lat: office.lat + 0.004, lon: office.lon)      // about 440 m
        let clusters = PlaceLogic.clusters(from: [heard("a", "x", at: office), heard("b", "x", at: near), heard("c", "x", at: far)], places: [])
        #expect(clusters.map(\.count) == [2, 1])
    }

    @Test func whereWasIQuestionsAreRecognisedAndGiveTheMomentToFind() {
        #expect(WhereQuestion.rest(of: "Where was I when I promised to send the spec?") == "I promised to send the spec")
        #expect(WhereQuestion.rest(of: "where were we when Priya mentioned Lisbon") == "Priya mentioned Lisbon")
        #expect(WhereQuestion.rest(of: "Where was I during the lease call?") == "the lease call")
        for q in ["Where is Priya going in March?", "When was I at the office?", "Where was I", "What did I say?", "Where was it?"] {
            #expect(WhereQuestion.rest(of: q) == nil, "\(q)")
        }
    }
}

@MainActor
struct PlacesModelTests {
    private func model() throws -> (PlacesModel, ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-places-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        return (PlacesModel(store: store), store, dir)
    }

    private func cluster(_ spot: Coordinate, place: Place? = nil) -> PlaceCluster { PlaceCluster(id: "c", coordinate: spot, momentIDs: ["a"], place: place) }

    @Test func aSpotCanBeNamedRenamedAndItsNameForgotten() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        let placed = try #require(await m.name(cluster(office), as: "  The office "))
        #expect(placed.name == "The office" && m.places.count == 1)
        let renamed = try #require(await m.name(cluster(office, place: placed), as: "Work"))
        #expect(renamed.id == placed.id && m.places.map(\.name) == ["Work"], "naming a named place renames it")
        let nothing = await m.name(cluster(cafe), as: "   ")
        #expect(nothing == nil && m.places.count == 1)
        let saved = await store.places()
        #expect(saved.map(\.name) == ["Work"])
        await m.forget(placed.id)
        let after = await store.places()
        #expect(m.places.isEmpty && after.isEmpty)
    }

    @Test func neverRecordHereHoldsAcrossARelaunchAndOnlyNearThePlace() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = try #require(await m.name(cluster(office), as: "Clinic"))
        #expect(!m.isNoRecord(at: office))
        await m.setNoRecord(p.id, true)
        #expect(m.isNoRecord(at: office) && m.isNoRecord(at: Coordinate(lat: 12.9718, lon: 77.5948)))
        #expect(!m.isNoRecord(at: cafe) && !m.isNoRecord(at: nil))
        let reopened = PlacesModel(store: store)
        await reopened.load()
        #expect(reopened.isNoRecord(at: office), "the choice is still there")
        await reopened.setNoRecord(p.id, false)
        #expect(!reopened.isNoRecord(at: office))
    }

    @Test func aMomentsLabelIsItsPlacesNameWhenItHasOne() async throws {
        let (m, _, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        _ = await m.name(cluster(home), as: "Home")
        #expect(m.label(for: heard("a", "x", at: home)) == "Home")
        #expect(m.label(for: heard("b", "x", at: cafe)) == nil && m.label(for: heard("c", "x", at: nil)) == nil)
    }

    @Test func momentsKeepTheirCoordinateInTheStore() async throws {
        let (_, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(heard("a", "x", at: office.coarse()))
        await store.upsert(heard("b", "x", at: nil, wall: 200))
        let back = await store.all()
        #expect(back.first { $0.id == "a" }?.coordinate == office.coarse() && back.first { $0.id == "b" }?.coordinate == nil)
        let first = try #require(back.first { $0.id == "a" })
        var rewritten = first; rewritten.transcript = "changed"
        await store.upsert(rewritten)
        let still = await store.all().first { $0.id == "a" }?.coordinate
        #expect(still == office.coarse(), "rewriting the moment as it is processed keeps where it was")
    }

    @Test func whatIsHeardInANeverRecordPlaceIsDroppedBeforeItIsLookedAt() async throws {
        let (m, store, dir) = try model()
        defer { try? FileManager.default.removeItem(at: dir) }
        let p = try #require(await m.name(cluster(office), as: "Clinic"))
        await m.setNoRecord(p.id, true)
        let pipelineModel = PipelineModel(store: store, defaults: UserDefaults(suiteName: "echo-nr-\(UUID().uuidString)")!)
        let pipeline = Pipeline(model: pipelineModel)
        pipeline.places = m
        let record = ChunkRecord(id: "secret", index: 0, wallStart: 100, fileOffset: 0, duration: 4, peakDb: -10, meanDb: -20, audioFile: "secret.m4a",
                                 status: .received, speechConfidence: nil, confirmedSeconds: 0, transcript: nil, dayId: DayID.today(), coordinate: office)
        try await store.write(audio: Data([1, 2, 3, 4]), named: "secret.m4a")
        pipelineModel.put(record)
        pipeline.enqueue(record)
        for _ in 0..<100 where pipelineModel.record(id: "secret")?.status != .dropped { try await Task.sleep(for: .milliseconds(20)) }
        #expect(pipelineModel.record(id: "secret")?.status == .dropped && pipelineModel.record(id: "secret")?.transcript == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.appending(path: "chunks/secret.m4a").path), "the audio is deleted")
    }
}

@MainActor
struct WhereWasITests {
    private func rig() async throws -> (AskModel, ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-where-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = ChunkStore(directory: dir)
        for c in [heard("promise", "Right I will send you the API specification by Wednesday noon.", at: office),
                  heard("lunch", "I finally booked the trip to Lisbon in March.", at: cafe, wall: 200),
                  heard("nowhere", "The plumber is coming on Friday at ten.", at: nil, wall: 300)] {
            await store.upsert(c)
            await store.index(id: c.id, normalizedText: TextNormalizer.normalized(c.transcript ?? ""), embedding: Embedder.vector(for: c.transcript ?? ""))
        }
        let ledger = LedgerModel(store: store, defaults: UserDefaults(suiteName: "echo-where-\(UUID().uuidString)")!)
        let ask = AskModel(store: store, ledger: ledger, client: StubMuseClient(), model: "m")
        let history = AskHistoryModel(store: store)
        ask.history = history
        return (ask, store, dir)
    }

    @Test func aNamedPlaceIsTheAnswerAndNothingLeavesThePhone() async throws {
        let (ask, store, dir) = try await rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        ask.spotFor = { $0.coordinate == office ? .named("The office") : .unnamed }
        await ask.ask("Where was I when I promised to send the API specification?")
        guard case .answered(let result) = ask.state else { Issue.record("expected a local answer, got \(ask.state)"); return }
        #expect(result.answer?.headline == "You were at The office." && result.decision.tier == .local)
        let history = await store.history()
        #expect(history.first?.source == .local && history.first?.shortAnswer == "You were at The office.")
        #expect(history.first?.detail.sourceChunkIDs == ["promise"])
    }

    @Test func anUnnamedPlaceSaysHowToNameIt() async throws {
        let (ask, _, dir) = try await rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        ask.spotFor = { _ in .unnamed }
        await ask.ask("Where was I when I booked the trip to Lisbon?")
        guard case .answered(let result) = ask.state else { Issue.record("expected an answer"); return }
        #expect(result.answer?.headline.contains("haven't named") == true)
    }

    @Test func aMomentWithNoPlaceFallsBackToTheUsualAnswerRatherThanGuessing() async throws {
        let (ask, _, dir) = try await rig()
        defer { try? FileManager.default.removeItem(at: dir) }
        ask.spotFor = { $0.coordinate == nil ? nil : .unnamed }
        await ask.ask("Where was I when the plumber was coming?")
        guard case .answered(let result) = ask.state else { Issue.record("expected an answer"); return }
        let headline = result.answer?.headline ?? ""
        #expect(!headline.hasPrefix("You were at"), "it didn't invent a place")
    }
}
