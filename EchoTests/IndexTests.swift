import Foundation
import Testing
@testable import Echo

struct NormalizerTests {
    @Test func numbersAndPercentsMatchAcrossSpokenAndWrittenForms() {
        #expect(TextNormalizer.contentTokens("four percent rent increase") == TextNormalizer.contentTokens("a 4% rent increase"))
        #expect(TextNormalizer.contentTokens("Friday at ten") == TextNormalizer.contentTokens("Friday at 10"))
        #expect(TextNormalizer.contentTokens("November twentieth") == TextNormalizer.contentTokens("November 20th"))
        #expect(TextNormalizer.contentTokens("December thirty first") == TextNormalizer.contentTokens("December 31"))
        #expect(TextNormalizer.contentTokens("November fourteenth") == TextNormalizer.contentTokens("November 14"))
    }

    @Test func titlesAreAliased() {
        #expect(TextNormalizer.contentTokens("Mister Brennan") == TextNormalizer.contentTokens("Mr. Brennan"))
        #expect(TextNormalizer.contentTokens("Doctor Okafor") == TextNormalizer.contentTokens("Dr. Okafor"))
    }

    @Test func stopwordsAndLoneOneAreDropped() {
        let tokens = TextNormalizer.contentTokens("What did I say about the one risk?")
        #expect(tokens == ["risk"])
    }

    @Test func contractionsStaySingleWords() {
        #expect(TextNormalizer.contentTokens("let's not add features") == ["add", "features"])
    }
}

struct IndexTests {
    private func makeStore() -> (ChunkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "echo-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (ChunkStore(directory: dir), dir)
    }

    private func record(_ id: String, _ index: Int, text: String) -> ChunkRecord {
        ChunkRecord(id: id, index: index, wallStart: 54_000 + Double(index), fileOffset: Double(index) * 5, duration: 4,
                    peakDb: -20, meanDb: -28, audioFile: "\(id).m4a", status: .stored, speechConfidence: 0.9,
                    confirmedSeconds: 3.5, transcript: text)
    }

    @Test func ftsFindsStemmedMatchesAndRanksBetterMatchesFirst() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let texts = [
            "a": "I have booked a plumber to come on Friday at 10 in the morning",
            "b": "Lisbon the second week of March",
            "c": "Friday at 10 works I will make sure I am home",
        ]
        for (i, (id, text)) in texts.sorted(by: { $0.key < $1.key }).enumerated() {
            await store.upsert(record(id, i, text: text))
            await store.index(id: id, normalizedText: TextNormalizer.normalized(text), embedding: Embedder.vector(for: text))
        }
        let plumbers = await store.ftsSearch(tokens: ["plumbers"])
        #expect(plumbers.map(\.id) == ["a"], "porter stemming should map plumbers -> plumber")

        let friday = await store.ftsSearch(tokens: TextNormalizer.contentTokens("plumber friday at ten"))
        #expect(friday.first?.id == "a")
        #expect(Set(friday.map(\.id)) == ["a", "c"])
    }

    @Test func statusUpdatesDoNotWipeTheEmbedding() async throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        var chunk = record("x", 0, text: "I will call grandma on Sunday")
        await store.upsert(chunk)
        await store.index(id: "x", normalizedText: TextNormalizer.normalized(chunk.transcript!), embedding: Embedder.vector(for: chunk.transcript!))
        #expect(await store.embeddings()["x"] != nil)

        chunk.status = .asr           // the pipeline re-upserts the row as it advances
        await store.upsert(chunk)
        #expect(await store.embeddings()["x"] != nil)
    }

    @Test func resetClearsRowsAndIndex() async {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        await store.upsert(record("x", 0, text: "plumber"))
        await store.index(id: "x", normalizedText: "plumber", embedding: nil)
        await store.reset()
        #expect(await store.all().isEmpty)
        #expect(await store.ftsSearch(tokens: ["plumber"]).isEmpty)
        #expect(await store.indexedIDs().isEmpty)
    }

    @Test func embeddingsSerializeAndRankRelatedTextCloser() throws {
        let corpus = [
            "I have booked a plumber to come on Friday at 10 in the morning",
            "Friday at 10 works I will make sure I am home to let them in",
            "I finally booked the trip Lisbon the second week of March",
            "Wonderful now about your lease It ends on December 31",
            "I can offer a 12 month renewal with a 4% rent increase",
            "Perfect budget is tight so lets not add new features before the lunch",
            "One risk the payment provider changes their format on November 8",
            "I will call grandma this Sunday afternoon I promise",
            "We also need groceries eggs olive oil and oranges for the juice",
            "Your mother birthday is on November 14 and I want to take her to the lake cabin",
            "Great I will review the design document on Tuesday and leave comments",
            "I will send the soup recipe this evening I promise",
        ]
        let vectors = corpus.map { Embedder.vector(for: $0)! }
        #expect(Embedder.deserialize(Embedder.serialize(vectors[0])) == vectors[0])

        let mean = Embedder.mean(of: vectors)
        var report = ""
        var plumberRankOK = 0
        for (query, expected) in [("when is the plumber coming", 0), ("where is the trip in March", 2),
                                  ("what did he say about the lease", 3), ("who will call grandma", 7)] {
            let q = try #require(Embedder.vector(for: query))
            let ranked = vectors.enumerated().map { ($0.offset, Embedder.centeredCosine(q, $0.element, mean: mean)) }
                .sorted { $0.1 > $1.1 }
            let rank = ranked.firstIndex { $0.0 == expected }! + 1
            if rank <= 3 { plumberRankOK += 1 }
            report += "'\(query)' -> expected #\(expected) ranked \(rank); top: \(ranked.prefix(3).map { "\($0.0):\(String(format: "%.2f", $0.1))" })\n"
        }
        try? report.write(toFile: "/tmp/echo_embed_report.txt", atomically: true, encoding: .utf8)
        #expect(plumberRankOK >= 3, "semantic leg alone should put the answer in the top 3 for most queries:\n\(report)")
    }
}
