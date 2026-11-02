import Foundation

/// A spot on the map, coarse on purpose: three decimal places is about a hundred metres, enough to tell home from the office
/// and not enough to say which room.
nonisolated struct Coordinate: Codable, Equatable, Hashable, Sendable {
    var lat: Double
    var lon: Double

    /// Rounded to roughly 110 m.
    func coarse() -> Coordinate { Coordinate(lat: (lat * 1_000).rounded() / 1_000, lon: (lon * 1_000).rounded() / 1_000) }

    /// Distance in metres (haversine).
    func distance(to other: Coordinate) -> Double {
        let r = 6_371_000.0
        let p1 = lat * .pi / 180, p2 = other.lat * .pi / 180
        let dp = (other.lat - lat) * .pi / 180, dl = (other.lon - lon) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, a.squareRoot()))
    }
}
