import CoreLocation
import Foundation

/// Where the watch is, for stamping what it hears with a place (coarse: about a hundred metres). Only while it is capturing.
@MainActor
final class WatchLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var latest: Coordinate?

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() { manager.stopUpdatingLocation() }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let spot = Coordinate(lat: last.coordinate.latitude, lon: last.coordinate.longitude).coarse()
        Task { @MainActor in self.latest = spot }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
