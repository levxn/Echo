import Foundation
import Observation

/// The places the person has named, and what to do at them. Everything stays on this phone.
@MainActor
@Observable
final class PlacesModel {
    private(set) var places: [Place] = []
    private let store: ChunkStore

    init(store: ChunkStore) { self.store = store }

    func load() async { places = await store.places() }

    /// Names a spot: the first time creates the place there, naming it again renames it.
    @discardableResult
    func name(_ cluster: PlaceCluster, as name: String) async -> Place? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var place = cluster.place ?? Place(id: UUID().uuidString, name: trimmed, coordinate: cluster.coordinate)
        place.name = trimmed
        if let i = places.firstIndex(where: { $0.id == place.id }) { places[i] = place } else { places.append(place) }
        await store.savePlace(place)
        return place
    }

    /// "Never record here": Echo keeps nothing heard in this place.
    func setNoRecord(_ id: String, _ on: Bool) async {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        places[i].noRecord = on
        await store.savePlace(places[i])
    }

    /// Forgets a place's name (its moments stay, as an unnamed place).
    func forget(_ id: String) async {
        places.removeAll { $0.id == id }
        await store.deletePlace(id: id)
    }

    func clear() async {
        places = []
        await store.clearPlaces()
    }

    func place(for spot: Coordinate?) -> Place? { PlaceLogic.place(for: spot, in: places) }
    func isNoRecord(at spot: Coordinate?) -> Bool { place(for: spot)?.noRecord == true }

    /// "At the office", for a moment, when its place has a name.
    func label(for chunk: ChunkRecord) -> String? { place(for: chunk.coordinate)?.name }
}
