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
    case hideAndSeek
    case higherOrLower
    case repeatAfterMe

    var displayName: String {
        switch self {
        case .senseOfDirection: return "Sense of Direction"
        case .hideAndSeek: return "Hide & Seek"
        case .higherOrLower: return "Higher or Lower"
        case .repeatAfterMe: return "Repeat After Me"
        }
    }

    /// A game can only be chosen when at least this many players have joined.
    var minPlayers: Int {
        switch self {
        case .senseOfDirection: return 2
        case .hideAndSeek: return 2
        case .higherOrLower: return 2
        case .repeatAfterMe: return 2
        }
    }

    var iconName: String {
        switch self {
        case .senseOfDirection: return "location.north.circle.fill"
        case .hideAndSeek: return "eye.slash.fill"
        case .higherOrLower: return "arrow.up.arrow.down"
        case .repeatAfterMe: return "square.grid.2x2.fill"
        }
    }

    var introText: String {
        switch self {
        case .senseOfDirection:
            return "A place will appear. Point the arrow toward it — closest direction wins the point. First to \(GameTiming.pointsToWinRound) points takes the round."
        case .hideAndSeek:
            return "Pick a hiding spot on the grid. Then everyone takes turns searching squares — the last player to be found wins the round."
        case .higherOrLower:
            return "A card is revealed. Call the next one higher or lower — wrong and you're out. Last player standing takes the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .repeatAfterMe:
            return "Watch the pads flash, then tap the sequence back from memory. One mistake and you're out — last player standing takes the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        }
    }

    static func available(for playerCount: Int) -> [MiniGameType] {
        allCases.filter { playerCount >= $0.minPlayers }
    }

    /// The smallest minimum across all games — below this, no round can be
    /// played at all, so a game can't start.
    static var smallestMinimum: Int {
        allCases.map(\.minPlayers).min() ?? 2
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

    // Hide & Seek
    static let hideSeconds: Double = 15
    static let seekSeconds: Double = 15
    static let seekRevealSeconds: Double = 6

    // Higher or Lower
    static let guessSeconds: Double = 10
    static let cardRevealSeconds: Double = 6

    // Repeat After Me
    static let sequenceStartLength = 3
    static let sequenceFlashSeconds: Double = 0.65
    static let sequenceRevealSeconds: Double = 6
}
