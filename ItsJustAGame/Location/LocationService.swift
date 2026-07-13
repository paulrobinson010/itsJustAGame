import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private(set) var heading: Double?
    private(set) var lastCoordinate: Coordinate?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<Coordinate?, Never>] = []

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// One-shot coordinate. Returns the last known fix if permission is
    /// denied or no fresh fix arrives. Never waits more than a few
    /// seconds: Core Location can silently keep retrying an unknown
    /// location (the simulator with no simulated location does exactly
    /// this), and a fix that never comes must not wedge a game flow.
    func currentCoordinate() async -> Coordinate? {
        if authorization == .denied || authorization == .restricted {
            return lastCoordinate
        }
        if authorization == .notDetermined {
            requestPermission()
        }
        manager.requestLocation()
        Task {
            try? await Task.sleep(for: .seconds(4))
            resumeWaiters(with: lastCoordinate)
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func startHeadingUpdates() {
        manager.startUpdatingHeading()
    }

    func stopHeadingUpdates() {
        manager.stopUpdatingHeading()
        heading = nil
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Coordinate(location.coordinate)
        Task { @MainActor in
            self.lastCoordinate = coordinate
            self.resumeWaiters(with: coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.resumeWaiters(with: self.lastCoordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in
            self.heading = value
        }
    }

    private func resumeWaiters(with coordinate: Coordinate?) {
        let pending = waiters
        waiters = []
        for waiter in pending {
            waiter.resume(returning: coordinate)
        }
    }
}
