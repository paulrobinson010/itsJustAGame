import CoreLocation
import Foundation

enum DirectionMath {
    /// Initial great-circle bearing from one coordinate to another, in
    /// degrees clockwise from true north (0..<360).
    static func initialBearing(from: Coordinate, to: Coordinate) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return normalize(atan2(y, x) * 180 / .pi)
    }

    /// Smallest angle between two bearings, 0...180.
    static func angularError(_ a: Double, _ b: Double) -> Double {
        let difference = abs(normalize(a) - normalize(b))
        return difference > 180 ? 360 - difference : difference
    }

    static func normalize(_ degrees: Double) -> Double {
        var d = degrees.truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return d
    }

    /// Point reached by travelling `distanceMeters` from `from` along a
    /// great circle at the given bearing. Used to draw guess rays on the map.
    static func destination(from: Coordinate, bearing: Double, distanceMeters: Double) -> Coordinate {
        let earthRadius = 6_371_000.0
        let angular = distanceMeters / earthRadius
        let theta = bearing * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(theta))
        let lon2 = lon1 + atan2(sin(theta) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return Coordinate(latitude: lat2 * 180 / .pi, longitude: normalizeLongitude(lon2 * 180 / .pi))
    }

    static func normalizeLongitude(_ longitude: Double) -> Double {
        var l = longitude.truncatingRemainder(dividingBy: 360)
        if l > 180 { l -= 360 }
        if l < -180 { l += 360 }
        return l
    }

    static func distanceMeters(from: Coordinate, to: Coordinate) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    static func compassLabel(_ bearing: Double) -> String {
        let directions = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                          "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let index = Int((normalize(bearing) + 11.25) / 22.5) % 16
        return directions[index]
    }
}

/// Fallback targets for when MapKit search near the players comes up dry
/// (or no player has shared a location).
enum CuratedLandmarks {
    static let all: [TargetLocation] = [
        TargetLocation(name: "Eiffel Tower, Paris", coordinate: Coordinate(latitude: 48.8584, longitude: 2.2945)),
        TargetLocation(name: "Statue of Liberty, New York", coordinate: Coordinate(latitude: 40.6892, longitude: -74.0445)),
        TargetLocation(name: "Big Ben, London", coordinate: Coordinate(latitude: 51.5007, longitude: -0.1246)),
        TargetLocation(name: "Sydney Opera House", coordinate: Coordinate(latitude: -33.8568, longitude: 151.2153)),
        TargetLocation(name: "Colosseum, Rome", coordinate: Coordinate(latitude: 41.8902, longitude: 12.4922)),
        TargetLocation(name: "Great Pyramid of Giza", coordinate: Coordinate(latitude: 29.9792, longitude: 31.1342)),
        TargetLocation(name: "Taj Mahal, Agra", coordinate: Coordinate(latitude: 27.1751, longitude: 78.0421)),
        TargetLocation(name: "Golden Gate Bridge, San Francisco", coordinate: Coordinate(latitude: 37.8199, longitude: -122.4783)),
        TargetLocation(name: "Christ the Redeemer, Rio de Janeiro", coordinate: Coordinate(latitude: -22.9519, longitude: -43.2105)),
        TargetLocation(name: "Mount Fuji, Japan", coordinate: Coordinate(latitude: 35.3606, longitude: 138.7274)),
        TargetLocation(name: "Table Mountain, Cape Town", coordinate: Coordinate(latitude: -33.9628, longitude: 18.4098)),
        TargetLocation(name: "Burj Khalifa, Dubai", coordinate: Coordinate(latitude: 25.1972, longitude: 55.2744)),
        TargetLocation(name: "Machu Picchu, Peru", coordinate: Coordinate(latitude: -13.1631, longitude: -72.5450)),
        TargetLocation(name: "Niagara Falls", coordinate: Coordinate(latitude: 43.0962, longitude: -79.0377)),
        TargetLocation(name: "Stonehenge, England", coordinate: Coordinate(latitude: 51.1789, longitude: -1.8262)),
        TargetLocation(name: "Edinburgh Castle, Scotland", coordinate: Coordinate(latitude: 55.9486, longitude: -3.1999)),
        TargetLocation(name: "Angkor Wat, Cambodia", coordinate: Coordinate(latitude: 13.4125, longitude: 103.8670)),
        TargetLocation(name: "Red Square, Moscow", coordinate: Coordinate(latitude: 55.7539, longitude: 37.6208)),
        TargetLocation(name: "Brandenburg Gate, Berlin", coordinate: Coordinate(latitude: 52.5163, longitude: 13.3777)),
        TargetLocation(name: "Sagrada Família, Barcelona", coordinate: Coordinate(latitude: 41.4036, longitude: 2.1744)),
        TargetLocation(name: "Mount Everest", coordinate: Coordinate(latitude: 27.9881, longitude: 86.9250)),
        TargetLocation(name: "Grand Canyon, Arizona", coordinate: Coordinate(latitude: 36.1069, longitude: -112.1129)),
        TargetLocation(name: "Uluru, Australia", coordinate: Coordinate(latitude: -25.3444, longitude: 131.0369)),
        TargetLocation(name: "Petra, Jordan", coordinate: Coordinate(latitude: 30.3285, longitude: 35.4444)),
        TargetLocation(name: "Acropolis, Athens", coordinate: Coordinate(latitude: 37.9715, longitude: 23.7267)),
        TargetLocation(name: "Times Square, New York", coordinate: Coordinate(latitude: 40.7580, longitude: -73.9855)),
        TargetLocation(name: "Buckingham Palace, London", coordinate: Coordinate(latitude: 51.5014, longitude: -0.1419)),
        TargetLocation(name: "Loch Ness, Scotland", coordinate: Coordinate(latitude: 57.3229, longitude: -4.4244)),
        TargetLocation(name: "Giant's Causeway, Northern Ireland", coordinate: Coordinate(latitude: 55.2408, longitude: -6.5116)),
        TargetLocation(name: "Niagara-on-the-Lake Clock Tower", coordinate: Coordinate(latitude: 43.2557, longitude: -79.0715)),
    ]
}
