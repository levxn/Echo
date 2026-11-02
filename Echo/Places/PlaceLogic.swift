import Foundation

/// A place the person has named ("Home", "The office"), with whether Echo must not record there. Kept on this phone.
struct Place: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var coordinate: Coordinate
    /// Anything within this many metres counts as being here.
    var radius: Double = PlaceLogic.radius
    /// Echo keeps nothing heard here.
    var noRecord = false
    var created: Date = Date()
}

/// Moments that happened in the same spot, named or not.
struct PlaceCluster: Identifiable, Equatable {
    let id: String
    let coordinate: Coordinate
    let momentIDs: [String]
    /// The name the person gave it, if they have.
    let place: Place?
    var count: Int { momentIDs.count }
    var title: String { place?.name ?? "Unnamed place" }
}

nonisolated enum PlaceLogic {
    static let radius = 150.0
}

extension PlaceLogic {
    /// The named place `spot` is in (the nearest, if several overlap).
    static func place(for spot: Coordinate?, in places: [Place]) -> Place? {
        guard let spot else { return nil }
        return places.filter { spot.distance(to: $0.coordinate) <= $0.radius }.min { spot.distance(to: $0.coordinate) < spot.distance(to: $1.coordinate) }
    }

    /// Groups what was heard by where: each named place is one group, and the rest gather into groups of moments within
    /// `radius` of each other. Most-heard first.
    static func clusters(from chunks: [ChunkRecord], places: [Place]) -> [PlaceCluster] {
        var byPlace: [String: [String]] = [:]
        var loose: [(centre: Coordinate, count: Int, ids: [String])] = []
        for chunk in chunks where chunk.status == .stored && chunk.coordinate != nil {
            let spot = chunk.coordinate!
            if let named = place(for: spot, in: places) { byPlace[named.id, default: []].append(chunk.id); continue }
            if let i = loose.firstIndex(where: { $0.centre.distance(to: spot) <= radius }) {
                let n = Double(loose[i].count)
                loose[i].centre = Coordinate(lat: (loose[i].centre.lat * n + spot.lat) / (n + 1), lon: (loose[i].centre.lon * n + spot.lon) / (n + 1))
                loose[i].count += 1
                loose[i].ids.append(chunk.id)
            } else {
                loose.append((spot, 1, [chunk.id]))
            }
        }
        var out = places.compactMap { p in byPlace[p.id].map { PlaceCluster(id: p.id, coordinate: p.coordinate, momentIDs: $0, place: p) } }
        out += loose.map { PlaceCluster(id: "spot-\($0.ids[0])", coordinate: $0.centre.coarse(), momentIDs: $0.ids, place: nil) }
        return out.sorted { $0.count != $1.count ? $0.count > $1.count : $0.id < $1.id }
    }
}

/// "Where was I when…?": the part of the question that says what moment to look for, or nil if it isn't that kind of question.
nonisolated enum WhereQuestion {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^\s*where (?:was|were) (?:i|we)\b\s*(?:when|while|at the time|during|for)?\s*(.*?)[\?\.\s]*$"#, options: .caseInsensitive)

    static func rest(of question: String) -> String? {
        let ns = question as NSString
        guard let m = pattern.firstMatch(in: question, range: NSRange(location: 0, length: ns.length)), m.numberOfRanges > 1 else { return nil }
        let rest = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? nil : rest
    }
}
