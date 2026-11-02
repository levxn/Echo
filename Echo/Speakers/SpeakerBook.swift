import Foundation

/// One voice the phone has learned to tell apart. A name and "this is me" are the person's own, added by hand.
struct Voice: Identifiable, Equatable, Sendable {
    var id: String
    /// "Voice 1", "Voice 2": what it is called until it has a name.
    var label: String
    var name: String?
    var isMe: Bool
    var centroid: VoicePrint
    var count: Int
    var colorIndex: Int
    var created: Date

    /// What to call them on screen.
    var display: String { name?.isEmpty == false ? name! : label }
    /// One character for a small circle: the name's first letter, or the voice's number until it has a name.
    var initial: String {
        if name?.isEmpty == false { return String(display.prefix(1)).uppercased() }
        return String(label.filter(\.isNumber).suffix(2)).isEmpty ? String(label.prefix(1)) : String(label.filter(\.isNumber).suffix(2))
    }
}

/// Works out whose voice each moment is, entirely on the phone: each new voiceprint joins the closest known voice if it is
/// near enough, otherwise it starts a new one. Pure logic; the phone saves the result.
struct SpeakerBook: Equatable {
    /// Closer than this is the same person. Chosen on the demo recordings (see `SpeakerTests`): with it, eight voices came
    /// out as eight, about 96% of the lines under the right one.
    static let threshold: Float = 1.8
    /// Two voices this close are probably one person heard twice; offered for merging.
    static let mergeThreshold: Float = 1.2

    var speakers: [Voice] = []

    /// Gives `print` to the closest voice (and nudges that voice toward it), or starts a new voice. Returns whose it is.
    @discardableResult
    mutating func assign(_ print: VoicePrint, now: Date = Date()) -> Voice {
        var best: (index: Int, distance: Float)?
        for (i, s) in speakers.enumerated() {
            let d = s.centroid.distance(to: print)
            if best == nil || d < best!.distance { best = (i, d) }
        }
        if let best, best.distance < Self.threshold {
            var s = speakers[best.index]
            let n = Float(s.count)
            s.centroid = VoicePrint(values: zip(s.centroid.values, print.values).map { ($0 * n + $1) / (n + 1) })
            s.count += 1
            speakers[best.index] = s
            return s
        }
        let number = (speakers.compactMap { Int($0.label.dropFirst(6)) }.max() ?? 0) + 1
        let s = Voice(id: UUID().uuidString, label: "Voice \(number)", name: nil, isMe: false, centroid: print, count: 1,
                        colorIndex: speakers.count % ProfileLogic.colorCount, created: now)
        speakers.append(s)
        return s
    }

    /// Voices that sound like each other, closest first, as `(a, b)` ids to offer merging.
    func mergeCandidates() -> [(a: String, b: String, distance: Float)] {
        var out: [(String, String, Float)] = []
        for i in 0..<speakers.count { for j in (i + 1)..<speakers.count {
            let d = speakers[i].centroid.distance(to: speakers[j].centroid)
            if d < Self.mergeThreshold { out.append((speakers[i].id, speakers[j].id, d)) }
        } }
        return out.sorted { $0.2 < $1.2 }
    }

    /// Folds `other` into `keep`: their moments, their weight, and a name or "me" if only one of them had it.
    mutating func merge(_ other: String, into keep: String) {
        guard other != keep, let a = speakers.firstIndex(where: { $0.id == keep }), let b = speakers.firstIndex(where: { $0.id == other }) else { return }
        var k = speakers[a]
        let o = speakers[b]
        let total = Float(k.count + o.count)
        k.centroid = VoicePrint(values: zip(k.centroid.values, o.centroid.values).map { ($0 * Float(k.count) + $1 * Float(o.count)) / total })
        k.count += o.count
        if (k.name ?? "").isEmpty { k.name = o.name }
        k.isMe = k.isMe || o.isMe
        speakers[a] = k
        speakers.remove(at: b)
    }

    /// There is only ever one "me".
    mutating func setMe(_ id: String?) {
        for i in speakers.indices { speakers[i].isMe = speakers[i].id == id }
    }

    var me: Voice? { speakers.first { $0.isMe } }
}
