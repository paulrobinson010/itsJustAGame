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
    /// Index into the player palette, dealt at random by the host when the
    /// game is created and used everywhere for the whole game. Optional so
    /// older games decode; they fall back to slot order.
    var colorIndex: Int?
    /// Simplification level for this player, nil when off. Set by the host
    /// at creation and carried into rematches.
    var assist: AssistLevel?
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
    case lightning
    case putYourFingerOnIt
    case tenSeconds
    case pushYourLuck
    case goldRush
    case eyeballIt
    case perfectCircle
    case sortCircuit

    var displayName: String {
        switch self {
        case .senseOfDirection: return "Sense of Direction"
        case .hideAndSeek: return "Hide & Seek"
        case .higherOrLower: return "Higher or Lower"
        case .repeatAfterMe: return "Repeat After Me"
        case .lightning: return "Lightning"
        case .putYourFingerOnIt: return "Put Your Finger On It"
        case .tenSeconds: return "Ten Seconds"
        case .pushYourLuck: return "Push Your Luck"
        case .goldRush: return "Gold Rush"
        case .eyeballIt: return "Eyeball It"
        case .perfectCircle: return "Perfect Circle"
        case .sortCircuit: return "Sort Circuit"
        }
    }

    /// A game can only be chosen when at least this many players have joined.
    var minPlayers: Int {
        switch self {
        case .senseOfDirection: return 2
        case .hideAndSeek: return 2
        case .higherOrLower: return 2
        case .repeatAfterMe: return 2
        case .lightning: return 2
        case .putYourFingerOnIt: return 2
        case .tenSeconds: return 2
        case .pushYourLuck: return 2
        case .goldRush: return 2
        case .eyeballIt: return 2
        case .perfectCircle: return 2
        case .sortCircuit: return 2
        }
    }

    var iconName: String {
        switch self {
        case .senseOfDirection: return "location.north.circle.fill"
        case .hideAndSeek: return "eye.slash.fill"
        case .higherOrLower: return "arrow.up.arrow.down"
        case .repeatAfterMe: return "square.grid.2x2.fill"
        case .lightning: return "bolt.fill"
        case .putYourFingerOnIt: return "hand.point.up.left.fill"
        case .tenSeconds: return "stopwatch.fill"
        case .pushYourLuck: return "dice.fill"
        case .goldRush: return "sparkles"
        case .eyeballIt: return "aqi.medium"
        case .perfectCircle: return "circle.dashed"
        case .sortCircuit: return "123.rectangle.fill"
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
        case .lightning:
            return "Wait for the flash, then tap as fast as you can — jump early and you're out of the running. Fastest finger takes the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .putYourFingerOnIt:
            return "A bare map appears and you're asked where a place is. Tap to drop your pin — closest to its capital takes the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .tenSeconds:
            return "The clock counts up, then hides. Keep counting in your head and tap at exactly the target. Closest wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .pushYourLuck:
            return "The pot grows one die at a time. Push to ride it or bank your share — but a skull wipes out everyone still riding. First to bank \(GameTiming.diceBankTarget) wins the round."
        case .goldRush:
            return "Same board, one secret pick each. Alone on a square? Pocket its coins. Share it? Nobody scores. First to \(GameTiming.goldTarget) coins wins the round."
        case .eyeballIt:
            return "A cloud of dots flashes up, then vanishes. How many were there? Closest guess wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .perfectCircle:
            return "Draw the roundest circle you can — one finger, one stroke. Highest score wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .sortCircuit:
            return "Nine numbers scattered on screen. Tap 1 to 9 as fast as you can — mistakes cost a second. Fastest wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        }
    }

    /// Chooser menu order: alphabetical by display name, however cases are
    /// declared and whatever gets added later.
    static var menu: [MiniGameType] {
        allCases.sorted { $0.displayName < $1.displayName }
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
    /// slot → iMessage address (phone number or email) for players picked
    /// from contacts. Host-only and local-only: used to address iMessage
    /// invites, never distributed.
    var inviteeAddresses: [Int: String]?
    /// Recorded when the game ends, so reopening shows the result
    /// instantly instead of replaying the whole stream.
    var summary: GameSummary?
    /// Rematch games begin automatically once everyone (re)joins.
    var autoStart: Bool?

    var id: String { gameID }
}

struct GameSummary: Codable, Hashable {
    var winner: Int
    var roundsWon: [Int: Int]
    var players: [PlayerInfo]
    var roundsToWin: Int

    func name(_ slot: Int) -> String {
        players.first { $0.slot == slot }?.name ?? "Player \(slot)"
    }
}

enum GameTiming {
    static let introSeconds: Double = 4
    static let aimSeconds: Double = 15
    static let revealSeconds: Double = 9
    static let betweenRoundsSeconds: Double = 7
    static let answerGraceSeconds: Double = 6
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

    // Lightning
    static let flashWaitMinSeconds: Double = 2
    static let flashWaitMaxSeconds: Double = 7
    static let tapWindowSeconds: Double = 4
    static let flashRevealSeconds: Double = 6

    // Put Your Finger On It
    static let fingerGuessSeconds: Double = 15
    static let fingerRevealSeconds: Double = 8

    // Ten Seconds
    static let clockVisibleSeconds: Double = 3
    static let clockRevealSeconds: Double = 6

    // Push Your Luck
    static let diceChooseSeconds: Double = 8
    static let diceRevealSeconds: Double = 5
    static let diceBankTarget = 20
    static let diceMaxRuns = 12

    // Gold Rush
    static let goldPickSeconds: Double = 12
    static let goldRevealSeconds: Double = 6
    static let goldTarget = 30
    static let goldMaxTurns = 15

    // Eyeball It
    static let eyeballVisibleSeconds: Double = 2
    static let eyeballGuessSeconds: Double = 12
    static let eyeballRevealSeconds: Double = 6

    // Perfect Circle
    static let circleDrawSeconds: Double = 10
    static let circleRevealSeconds: Double = 8

    // Sort Circuit
    static let sortMaxSeconds: Double = 30
    static let sortPenaltyMs = 1000
    static let sortRevealSeconds: Double = 6
}
