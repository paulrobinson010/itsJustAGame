import CoreLocation
import Foundation

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct PlayerInfo: Codable, Hashable, Identifiable {
    var slot: Int
    var name: String
    var id: Int { slot }
}

struct GameConfig: Codable, Hashable {
    var gameID: String
    var roundsToWin: Int
    var players: [PlayerInfo]
    var createdAt: Date

    func player(_ slot: Int) -> PlayerInfo? {
        players.first { $0.slot == slot }
    }

    func name(_ slot: Int) -> String {
        player(slot)?.name ?? "Player \(slot)"
    }
}

enum MiniGameType: String, Codable, CaseIterable, Hashable {
    case senseOfDirection

    var displayName: String {
        switch self {
        case .senseOfDirection: return "Sense of Direction"
        }
    }
}

/// What each device persists locally about a game it is part of. This is the
/// only place the encryption key lives outside an invite link.
struct SavedGame: Codable, Hashable, Identifiable {
    var gameID: String
    var keyBase64URL: String
    var mySlot: Int
    var isHost: Bool
    var hostConfig: GameConfig?
    var title: String
    var createdAt: Date
    /// True until a joiner has seen their "Welcome to the game" greeting.
    /// Optional so older saved games decode cleanly.
    var needsWelcome: Bool?

    var id: String { gameID }
}

enum GameTiming {
    static let introSeconds: Double = 4
    static let aimSeconds: Double = 15
    static let revealSeconds: Double = 12
    static let betweenRoundsSeconds: Double = 10
    static let answerGraceSeconds: Double = 8
    static let wheelSpinSeconds: Double = 5
    static let pointsToWinRound = 3
    static let maxTurnsPerRound = 10
}
