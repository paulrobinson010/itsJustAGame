import Foundation
import MapKit

/// Picks the turn's target place. Runs only on the host device: searches
/// MapKit for real places near a randomly chosen player, and falls back to
/// the curated landmark list when the search comes up dry.
enum LocationPicker {
    private static let searchTerms = [
        "landmark", "castle", "stadium", "museum",
        "cathedral", "monument", "famous park", "town",
    ]

    static func pickTarget(near playerCoordinates: [Coordinate], excluding usedNames: Set<String>) async -> TargetLocation {
        if let anchor = playerCoordinates.randomElement() {
            for _ in 0..<3 {
                if let found = await searchOnce(near: anchor, excluding: usedNames, players: playerCoordinates) {
                    return found
                }
            }
        }
        let fresh = CuratedLandmarks.all.filter {
            !usedNames.contains($0.name) && isFarEnough($0.coordinate, from: playerCoordinates)
        }
        return fresh.randomElement() ?? CuratedLandmarks.all.randomElement()!
    }

    private static func searchOnce(near anchor: Coordinate, excluding usedNames: Set<String>, players: [Coordinate]) async -> TargetLocation? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchTerms.randomElement()
        let radius = Double.random(in: 15_000...120_000)
        request.region = MKCoordinateRegion(
            center: anchor.clCoordinate,
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
        request.resultTypes = .pointOfInterest
        guard let response = try? await MKLocalSearch(request: request).start() else { return nil }
        let candidates = response.mapItems.compactMap { item -> TargetLocation? in
            guard let name = item.name, !name.isEmpty else { return nil }
            let coordinate = Coordinate(item.placemark.coordinate)
            guard !usedNames.contains(name), isFarEnough(coordinate, from: players) else { return nil }
            return TargetLocation(name: name, coordinate: coordinate)
        }
        return candidates.randomElement()
    }

    /// A target sitting on top of a player makes the bearing meaningless.
    private static func isFarEnough(_ target: Coordinate, from players: [Coordinate]) -> Bool {
        players.allSatisfy { DirectionMath.distanceMeters(from: $0, to: target) > 2_000 }
    }
}
