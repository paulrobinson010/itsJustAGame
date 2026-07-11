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
    // Sense of Direction
    case turnStart(TurnStart)
    case turnReveal(TurnReveal)
    // Hide & Seek
    case hideStart(HideStart)
    case seekTurn(SeekTurnStart)
    case seekReveal(SeekReveal)
    // Higher or Lower
    case cardTurn(CardTurn)
    case cardReveal(CardReveal)
    // Repeat After Me
    case sequenceTurn(SequenceTurn)
    case sequenceReveal(SequenceReveal)
    // Lightning
    case flashTurn(FlashTurn)
    case flashReveal(FlashReveal)
    // Put Your Finger On It
    case fingerTurn(FingerTurn)
    case fingerReveal(FingerReveal)
    /// Several players reached the winning round count together — the
    /// wheel decides the overall winner, totally at random (host rolled).
    case tieBreakSpin(candidates: [Int], winner: Int)
    case roundEnd(round: Int, winners: [Int], roundsWon: [Int: Int])
    case gameEnd(winner: Int, roundsWon: [Int: Int])
    /// A fresh game for the same crew, announced over this (old) game's
    /// encrypted stream — so nobody needs a new invite link. Carries the
    /// new game's key, sealed with the old one; keys still rotate per game.
    case rematch(RematchInvite)
}

struct RematchInvite: Codable, Hashable {
    var newGameID: String
    var newKeyBase64URL: String
    var config: GameConfig
}

/// Messages published by player devices at well-known record IDs the host
/// knows to poll for. Players never talk to each other directly — the host
/// folds their input into the next host message.
enum PlayerMessage: Codable {
    case join(slot: Int, name: String, coordinate: Coordinate?)
    case choice(round: Int, slot: Int, game: MiniGameType)
    case answer(DirectionAnswer)
    case hide(round: Int, slot: Int, cell: Int)
    case seek(round: Int, turn: Int, slot: Int, cell: Int)
    case guess(round: Int, match: Int, step: Int, slot: Int, guess: HigherLowerGuess)
    case sequenceAnswer(round: Int, match: Int, step: Int, slot: Int, taps: [Int])
    case reaction(round: Int, turn: Int, slot: Int, elapsedMs: Int?, falseStart: Bool)
    case fingerGuess(round: Int, turn: Int, slot: Int, coordinate: Coordinate)
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

// MARK: - Hide & Seek

struct HideStart: Codable, Hashable {
    var round: Int
    var gridSize: Int
    var startAt: Date
    var hideSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(hideSeconds) }
    var cellCount: Int { gridSize * gridSize }
}

struct SeekTurnStart: Codable, Hashable {
    var round: Int
    var turn: Int
    var seeker: Int
    var order: [Int]
    var gridSize: Int
    var startAt: Date
    var seekSeconds: Double
    var searched: [Int]
    /// slot -> cell where that player was found
    var found: [Int: Int]

    var deadline: Date { startAt.addingTimeInterval(seekSeconds) }
    var cellCount: Int { gridSize * gridSize }
}

struct SeekReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var seeker: Int
    var cell: Int
    var gridSize: Int
    /// Players revealed by this search.
    var revealed: [Int]
    var searched: [Int]
    var found: [Int: Int]
    var remainingHidden: [Int]
    /// Non-empty when the match ended. Several winners when the final
    /// search revealed the last hiders together — they share the round.
    var roundWinners: [Int]
    var nextTurnAt: Date?
}

// MARK: - Higher or Lower

enum CardSuit: String, Codable, CaseIterable, Hashable {
    case spades, hearts, diamonds, clubs
}

struct PlayingCard: Codable, Hashable {
    /// 1 (ace) through 13 (king). Ace is low.
    var rank: Int
    var suit: CardSuit
}

enum HigherLowerGuess: String, Codable, Hashable {
    case higher, lower
}

struct CardTurn: Codable, Hashable {
    var round: Int
    var match: Int
    var step: Int
    var card: PlayingCard
    var alive: [Int]
    var points: [Int: Int]
    var startAt: Date
    var guessSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(guessSeconds) }
}

struct CardReveal: Codable, Hashable {
    var round: Int
    var match: Int
    var step: Int
    var previousCard: PlayingCard
    var nextCard: PlayingCard
    var guesses: [Int: HigherLowerGuess]
    /// Eliminated by this reveal.
    var eliminated: [Int]
    /// Still standing after this reveal.
    var alive: [Int]
    /// Same rank twice — nobody is eliminated.
    var isTie: Bool
    /// Non-empty when the match ended; every winner scores a point.
    var matchWinners: [Int]
    var points: [Int: Int]
    /// Non-empty when someone (or several at once) reached the target points.
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Repeat After Me

struct SequenceTurn: Codable, Hashable {
    var round: Int
    var match: Int
    var step: Int
    /// Pad indices 0–3, replayed in full each turn (it grows by one).
    var sequence: [Int]
    var alive: [Int]
    var points: [Int: Int]
    var startAt: Date
    var watchSeconds: Double
    var answerSeconds: Double

    var watchEndsAt: Date { startAt.addingTimeInterval(watchSeconds) }
    var deadline: Date { startAt.addingTimeInterval(watchSeconds + answerSeconds) }
}

struct SequencePlayerResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// nil when the player never answered at all.
    var taps: [Int]?
    var correct: Bool
    var id: Int { slot }
}

struct SequenceReveal: Codable, Hashable {
    var round: Int
    var match: Int
    var step: Int
    var sequence: [Int]
    var results: [SequencePlayerResult]
    var eliminated: [Int]
    var alive: [Int]
    var matchWinners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Lightning

struct FlashTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// The host-rolled random moment the screen flashes. Reaction time is
    /// measured locally against this shared timestamp, so network latency
    /// never affects fairness.
    var flashAt: Date
    var tapWindowSeconds: Double

    var deadline: Date { flashAt.addingTimeInterval(tapWindowSeconds) }
}

struct FlashResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// nil = never tapped (unless falseStart).
    var elapsedMs: Int?
    var falseStart: Bool
    var id: Int { slot }
}

struct FlashReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [FlashResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Put Your Finger On It

struct FingerTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var regionName: String
    var regionCenter: Coordinate
    var regionSpanLat: Double
    var regionSpanLon: Double
    /// The place being asked about ("Where is Algeria?"). The capital
    /// coordinate stays on the host until the reveal.
    var placeName: String
    var points: [Int: Int]
    var startAt: Date
    var guessSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(guessSeconds) }
}

struct FingerOutcome: Codable, Hashable, Identifiable {
    var slot: Int
    var coordinate: Coordinate?
    var distanceKm: Double?
    var id: Int { slot }
}

struct FingerReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var regionName: String
    var placeName: String
    var capitalName: String
    var target: Coordinate
    var outcomes: [FingerOutcome]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
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

    static func hide(_ gameID: String, round: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-hide\(slot)"
    }

    static func seek(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-s\(turn)-seek\(slot)"
    }

    static func guess(_ gameID: String, round: Int, match: Int, step: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-m\(match)-s\(step)-hl\(slot)"
    }

    static func sequenceAnswer(_ gameID: String, round: Int, match: Int, step: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-m\(match)-q\(step)-seq\(slot)"
    }

    static func reaction(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-f\(turn)-tap\(slot)"
    }

    static func fingerGuess(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-p\(turn)-pin\(slot)"
    }
}
