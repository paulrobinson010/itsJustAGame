import Foundation

/// Messages published by the host device, sequenced as records h0, h1, h2…
///
/// Game state on every device is a pure fold over this stream, so any player
/// can rebuild the whole game at any time by replaying it from 0 — that is
/// how rejoining after an app relaunch works.
enum HostMessage: Codable {
    case gameCreated(config: GameConfig)
    case lobby(joined: [Int])
    case wheel(round: Int, chooser: Int)
    case roundStart(round: Int, game: MiniGameType)
    case turnStart(TurnStart)
    case turnReveal(TurnReveal)
    case roundEnd(round: Int, winner: Int, roundsWon: [Int: Int])
    case gameEnd(winner: Int, roundsWon: [Int: Int])
}

/// Messages published by player devices at well-known record IDs the host
/// knows to poll for. Players never talk to each other directly — the host
/// folds their input into the next host message.
enum PlayerMessage: Codable {
    case join(slot: Int, name: String, coordinate: Coordinate?)
    case choice(round: Int, slot: Int, game: MiniGameType)
    case answer(DirectionAnswer)
}

struct TargetLocation: Codable, Hashable {
    var name: String
    var coordinate: Coordinate
}

struct TurnStart: Codable, Hashable {
    var round: Int
    var turn: Int
    var target: TargetLocation
    var startAt: Date
    var introSeconds: Double
    var aimSeconds: Double

    var introEndsAt: Date { startAt.addingTimeInterval(introSeconds) }
    var deadline: Date { startAt.addingTimeInterval(introSeconds + aimSeconds) }
}

struct DirectionAnswer: Codable, Hashable {
    var round: Int
    var turn: Int
    var slot: Int
    var bearing: Double?
    var coordinate: Coordinate?
    var submittedAt: Date
}

struct PlayerOutcome: Codable, Hashable, Identifiable {
    var slot: Int
    var bearing: Double?
    var correctBearing: Double?
    var errorDegrees: Double?
    var coordinate: Coordinate?
    var id: Int { slot }
}

struct TurnReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var target: TargetLocation
    var outcomes: [PlayerOutcome]
    var winner: Int?
    var points: [Int: Int]
    var roundWinner: Int?
    var nextTurnAt: Date?
}

/// Deterministic record IDs. Everything is fetched by ID rather than by
/// query, so CloudKit needs no custom indexes or schema setup at all.
enum RecordName {
    static func host(_ gameID: String, seq: Int) -> String {
        "g\(gameID)-h\(seq)"
    }

    static func join(_ gameID: String, slot: Int) -> String {
        "g\(gameID)-join\(slot)"
    }

    static func choice(_ gameID: String, round: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-choice\(slot)"
    }

    static func answer(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-t\(turn)-ans\(slot)"
    }
}
