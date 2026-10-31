import Foundation
import NaturalLanguage

/// On-device word-vector embedding (Apple NaturalLanguage): the mean of the word vectors of a text's
/// content words, L2-normalized. This is not a sentence-embedding model; sentence and contextual
/// embeddings are unavailable in the simulator. Retrieval compensates with FTS5 and mean-centering.
nonisolated enum Embedder {
    nonisolated(unsafe) private static let words = NLEmbedding.wordEmbedding(for: .english)

    static var isAvailable: Bool { words != nil }

    /// Unit-length mean word vector for the text, or nil if none of its words has a vector.
    static func vector(for text: String) -> [Float]? {
        guard let words else { return nil }
        var sum: [Double] = []
        var n = 0
        for token in TextNormalizer.contentTokens(text) where Int(token) == nil {
            guard let v = words.vector(for: token) else { continue }
            if sum.isEmpty { sum = [Double](repeating: 0, count: v.count) }
            for i in 0..<v.count { sum[i] += v[i] }
            n += 1
        }
        guard n > 0 else { return nil }
        let norm = sqrt(sum.reduce(0) { $0 + $1 * $1 })
        guard norm > 0 else { return nil }
        return sum.map { Float($0 / norm) }
    }

    /// Mean of the given vectors, used to center cosine similarity.
    static func mean(of vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var m = [Float](repeating: 0, count: first.count)
        for v in vectors { for i in 0..<m.count { m[i] += v[i] } }
        return m.map { $0 / Float(vectors.count) }
    }

    /// Cosine similarity after subtracting `mean` from both vectors. Averaged word vectors all point in
    /// roughly the same direction, so raw cosine barely discriminates; centering removes that shared part.
    static func centeredCosine(_ a: [Float], _ b: [Float], mean: [Float]) -> Float {
        guard a.count == b.count, a.count == mean.count else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<a.count {
            let x = a[i] - mean[i], y = b[i] - mean[i]
            dot += x * y; na += x * x; nb += y * y
        }
        let d = (na * nb).squareRoot()
        return d > 0 ? dot / d : 0
    }

    static func serialize(_ v: [Float]) -> Data { v.withUnsafeBufferPointer { Data(buffer: $0) } }

    static func deserialize(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        return [Float](unsafeUninitializedCapacity: count) { buf, n in
            data.withUnsafeBytes { raw in
                for i in 0..<count { buf[i] = raw.loadUnaligned(fromByteOffset: i * 4, as: Float.self) }
            }
            n = count
        }
    }
}
