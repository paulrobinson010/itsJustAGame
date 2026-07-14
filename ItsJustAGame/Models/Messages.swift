import Foundation

/// Messages published by the host device, sequenced as records h0, h1, h2…
///
/// Game state on every device is a pure fold over this stream, so any player
/// can rebuild the whole game at any time by replaying it from 0 — that is
/// how rejoining after an app relaunch works.
enum HostMessage: Codable {
    case gameCreated(config: GameConfig)
    case lobby(joined: [Int])
    case wheel(round: Int, chooser: Int, spinSeconds: Double)
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
    // Ten Seconds
    case clockTurn(ClockTurn)
    case clockReveal(ClockReveal)
    // Push Your Luck
    case diceStep(DiceStep)
    case diceReveal(DiceReveal)
    // Gold Rush
    case goldTurn(GoldTurn)
    case goldReveal(GoldReveal)
    // Eyeball It
    case eyeballTurn(EyeballTurn)
    case eyeballReveal(EyeballReveal)
    // Perfect Circle
    case circleTurn(CircleTurn)
    case circleReveal(CircleReveal)
    // Sort Circuit
    case sortTurn(SortTurn)
    case sortReveal(SortReveal)
    // Steady Hand
    case steadyTurn(SteadyTurn)
    case steadyReveal(SteadyReveal)
    // Showdown
    case showdownTurn(ShowdownTurn)
    case showdownReveal(ShowdownReveal)
    // Tap Frenzy
    case frenzyTurn(FrenzyTurn)
    case frenzyReveal(FrenzyReveal)
    // Globetrotter
    case globeTurn(GlobeTurn)
    case globeReveal(GlobeReveal)
    // Colour Clash
    case clashTurn(ClashTurn)
    case clashReveal(ClashReveal)
    // Spirit Level
    case levelTurn(LevelTurn)
    case levelReveal(LevelReveal)
    // Pour It
    case pourTurn(PourTurn)
    case pourReveal(PourReveal)
    // Marble Maze
    case mazeTurn(MazeTurn)
    case mazeReveal(MazeReveal)
    // Loudest
    case loudTurn(LoudTurn)
    case loudReveal(LoudReveal)
    // Blow It Out
    case blowTurn(BlowTurn)
    case blowReveal(BlowReveal)
    // Hum It
    case humTurn(HumTurn)
    case humReveal(HumReveal)
    // Crack the Safe
    case safeTurn(SafeTurn)
    case safeReveal(SafeReveal)
    // Feel the Beat
    case beatTurn(BeatTurn)
    case beatReveal(BeatReveal)
    /// Several players reached the winning round count together — the
    /// wheel decides the overall winner, totally at random (host rolled).
    case tieBreakSpin(candidates: [Int], winner: Int, spinSeconds: Double)
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
    case clockTap(round: Int, turn: Int, slot: Int, elapsedMs: Int)
    case dice(round: Int, run: Int, step: Int, slot: Int, push: Bool)
    case goldPick(round: Int, turn: Int, slot: Int, cell: Int)
    case eyeball(round: Int, turn: Int, slot: Int, guess: Int)
    case circleDraw(round: Int, turn: Int, slot: Int, path: [Double])
    case sortTime(round: Int, turn: Int, slot: Int, elapsedMs: Int, mistakes: Int)
    case steadyTime(round: Int, turn: Int, slot: Int, survivedMs: Int)
    case showdownThrow(round: Int, turn: Int, slot: Int, throwing: RPSThrow)
    case frenzyTaps(round: Int, turn: Int, slot: Int, taps: Int)
    case globeGuess(round: Int, turn: Int, slot: Int, coordinate: Coordinate)
    case clashTime(round: Int, turn: Int, slot: Int, elapsedMs: Int, mistakes: Int)
    case levelError(round: Int, turn: Int, slot: Int, errorMilliDeg: Int)
    case pourFill(round: Int, turn: Int, slot: Int, fillPercent: Int, overflowed: Bool)
    case mazeTime(round: Int, turn: Int, slot: Int, elapsedMs: Int)
    case loudLevel(round: Int, turn: Int, slot: Int, level: Int)
    case blowCandles(round: Int, turn: Int, slot: Int, candles: Int)
    case humPitch(round: Int, turn: Int, slot: Int, errorCents: Int)
    case safeTime(round: Int, turn: Int, slot: Int, elapsedMs: Int)
    case beatError(round: Int, turn: Int, slot: Int, errorMs: Int)
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
    /// Simplify: unsearched cells nobody is hiding in, keyed by the
    /// (assisted) seeker they're for. Only that device shows them.
    var assistSafe: [Int: [Int]]?

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
    /// Simplify (top level): the actually-correct call, keyed by the
    /// assisted player it's for — the host pre-draws the next card.
    /// Absent on ties. Only that device shows it.
    var assistCorrect: [Int: HigherLowerGuess]?

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
    /// Simplify: a circle the capital sits inside (deliberately off-centre
    /// so it doesn't pinpoint it), keyed by the assisted player it's for.
    /// Only that device draws it.
    var assistHints: [Int: FingerHint]?

    var deadline: Date { startAt.addingTimeInterval(guessSeconds) }
}

struct FingerHint: Codable, Hashable {
    var center: Coordinate
    var radiusKm: Double
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

// MARK: - Ten Seconds

struct ClockTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// Tap when you think this many seconds have passed since startAt.
    var targetSeconds: Double
    /// The clock is visible for this long, then hides.
    var visibleSeconds: Double
    /// Give up waiting after this long.
    var maxSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(maxSeconds) }
}

struct ClockResult: Codable, Hashable, Identifiable {
    var slot: Int
    var elapsedMs: Int?
    var errorMs: Int?
    var id: Int { slot }
}

struct ClockReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var targetSeconds: Double
    var results: [ClockResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Push Your Luck

/// The pot wheel: five values and two busts, spread apart. The host spins
/// (picks an index); every device animates the same landing.
enum DiceWheel {
    /// Segment values clockwise from the pointer; nil is a 💀 bust.
    static let segments: [Int?] = [1, 4, nil, 2, 5, nil, 3]
}

struct DiceStep: Codable, Hashable {
    var round: Int
    var run: Int
    var step: Int
    var pot: Int
    /// Still riding this run; they must choose push or bank.
    var riders: [Int]
    /// Everyone's banked totals — the round score.
    var banks: [Int: Int]
    var startAt: Date
    var chooseSeconds: Double
    /// Simplify (top level): whether the pre-spun next wheel result is a
    /// bust, keyed by the assisted rider it's for. Only that device shows it.
    var assistPeek: [Int: Bool]?
    /// Riders the pot carried to the target this step — banked by the host
    /// automatically, since riding past a guaranteed win is pointless.
    var autoBanked: [Int]?

    var deadline: Date { startAt.addingTimeInterval(chooseSeconds) }
}

struct DiceReveal: Codable, Hashable {
    var round: Int
    var run: Int
    var step: Int
    /// The value the wheel added; nil when nobody rode or it was a bust.
    var die: Int?
    var isSkull: Bool
    /// Where the wheel landed (into DiceWheel.segments) and how long the
    /// spin plays — every device animates the identical landing. Nil when
    /// nobody rode, so no spin happened.
    var wheelIndex: Int?
    var spinSeconds: Double?
    var potBefore: Int
    var potAfter: Int
    /// slot -> pushed (true) or banked (false), for everyone who had to choose.
    var choices: [Int: Bool]
    var bankedNow: [Int]
    var riders: [Int]
    var banks: [Int: Int]
    var runOver: Bool
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Gold Rush

struct GoldTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var gridSize: Int
    /// Coin value per cell — the same board on every device.
    var coins: [Int]
    /// Everyone's pocketed coin totals — the round score.
    var totals: [Int: Int]
    var startAt: Date
    var pickSeconds: Double
    /// Simplify (levels 2–3): cells other players have already picked this
    /// turn, keyed by the assisted player they're for. The host re-publishes
    /// the turn as picks land, so they appear live. Level 3 devices also
    /// lock these cells. Only the assisted device shows its own.
    var assistTaken: [Int: [Int]]?

    var deadline: Date { startAt.addingTimeInterval(pickSeconds) }
    var cellCount: Int { gridSize * gridSize }
}

struct GoldReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var gridSize: Int
    var coins: [Int]
    /// slot -> picked cell, for everyone who picked.
    var picks: [Int: Int]
    /// Cells picked by two or more players — nobody scores those.
    var clashes: [Int]
    /// slot -> coins won this turn.
    var gains: [Int: Int]
    var totals: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Eyeball It

struct EyeballTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// True dot count — hidden by the UI until the reveal.
    var count: Int
    /// Every device regenerates the identical scatter from this seed.
    var seed: UInt64
    var visibleSeconds: Double
    var guessSeconds: Double

    var dotsEndAt: Date { startAt.addingTimeInterval(visibleSeconds) }
    var deadline: Date { startAt.addingTimeInterval(visibleSeconds + guessSeconds) }
}

struct EyeballResult: Codable, Hashable, Identifiable {
    var slot: Int
    var guess: Int?
    var error: Int?
    var id: Int { slot }
}

struct EyeballReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var count: Int
    var results: [EyeballResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Perfect Circle

struct CircleTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    var drawSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(drawSeconds) }
}

struct CircleResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// 0–100, scored by the host from the submitted stroke.
    var score: Double?
    /// The stroke itself (x0,y0,x1,y1… in unit square) so the reveal can
    /// show everyone's actual drawing.
    var path: [Double]?
    var id: Int { slot }
}

struct CircleReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [CircleResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Sort Circuit

struct SortTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// Every device regenerates the identical tile layout from this seed.
    var seed: UInt64
    var tileCount: Int
    var maxSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(maxSeconds) }
}

struct SortResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Includes mistake penalties; nil = never finished.
    var elapsedMs: Int?
    var mistakes: Int
    var id: Int { slot }
}

struct SortReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [SortResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Steady Hand

struct SteadyTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// Every device regenerates the identical ring drift from this seed.
    var seed: UInt64
    var maxSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(maxSeconds) }
}

struct SteadyResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// How long they stayed inside the ring; nil = never played.
    var survivedMs: Int?
    var id: Int { slot }
}

struct SteadyReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [SteadyResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Showdown

enum RPSThrow: String, Codable, CaseIterable, Hashable {
    case rock, paper, scissors

    var emoji: String {
        switch self {
        case .rock: return "🪨"
        case .paper: return "📄"
        case .scissors: return "✂️"
        }
    }

    var displayName: String {
        switch self {
        case .rock: return "Rock"
        case .paper: return "Paper"
        case .scissors: return "Scissors"
        }
    }

    /// The throw this one loses to.
    var beatenBy: RPSThrow {
        switch self {
        case .rock: return .paper
        case .paper: return .scissors
        case .scissors: return .rock
        }
    }

    func beats(_ other: RPSThrow) -> Bool {
        other.beatenBy == self
    }
}

struct ShowdownTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    /// Everyone's accumulated wins — the round score.
    var totals: [Int: Int]
    var startAt: Date
    var throwSeconds: Double
    /// Simplify (levels 2–3): what other players have thrown so far, keyed
    /// by the assisted player it's for. The host re-publishes the turn as
    /// throws land. Only the assisted device shows its own.
    var assistThrown: [Int: [Int: RPSThrow]]?

    var deadline: Date { startAt.addingTimeInterval(throwSeconds) }
}

struct ShowdownReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    /// slot -> throw, for everyone who threw.
    var thrown: [Int: RPSThrow]
    /// slot -> players beaten this turn.
    var gains: [Int: Int]
    var totals: [Int: Int]
    /// Top scorers of the turn (when anyone beat anyone).
    var winners: [Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Globetrotter

/// Reuses FingerHint (the off-centre hint circle) and FingerOutcome (a
/// player's pin + distance) — the map machinery is shared with Put Your
/// Finger On It; only the question differs (a world landmark, not a
/// region's capital).
struct GlobeTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    /// The landmark being asked about ("Where is the Taj Mahal?"). Its
    /// coordinate stays on the host until the reveal.
    var landmark: String
    var continent: String
    var points: [Int: Int]
    var startAt: Date
    var guessSeconds: Double
    /// Simplify: a circle the landmark sits inside (off-centre so it
    /// doesn't pinpoint it), keyed by the assisted player it's for.
    var assistHints: [Int: FingerHint]?

    var deadline: Date { startAt.addingTimeInterval(guessSeconds) }
}

struct GlobeReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var landmark: String
    var country: String
    var target: Coordinate
    var outcomes: [FingerOutcome]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Spirit Level

struct LevelTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// The roll angle (degrees) to line the bubble up with.
    var targetDegrees: Double
    var holdSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(holdSeconds) }
}

struct LevelResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Angular error at lock-in, in thousandths of a degree; nil = no lock.
    var errorMilliDeg: Int?
    var id: Int { slot }
}

struct LevelReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var targetDegrees: Double
    var results: [LevelResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Pour It

struct PourTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// Fill line to stop at, as a percentage of the glass.
    var targetPercent: Int
    var pourSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(pourSeconds) }
}

struct PourResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Final fill (0–100); nil = never poured.
    var fillPercent: Int?
    /// Spilled over the top.
    var overflowed: Bool
    var id: Int { slot }
}

struct PourReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var targetPercent: Int
    var results: [PourResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Marble Maze

struct MazeTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// Every device regenerates the identical maze from this seed.
    var seed: UInt64
    var size: Int
    var maxSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(maxSeconds) }
}

struct MazeResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Time to reach the exit; nil = never escaped.
    var elapsedMs: Int?
    var id: Int { slot }
}

struct MazeReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [MazeResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Loudest

struct LoudTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    var shoutSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(shoutSeconds) }
}

struct LoudResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Peak loudness 0–1000; nil = never shouted / no mic.
    var level: Int?
    var id: Int { slot }
}

struct LoudReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [LoudResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Blow It Out

struct BlowTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    var blowSeconds: Double
    var candles: Int

    var deadline: Date { startAt.addingTimeInterval(blowSeconds) }
}

struct BlowResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Candles blown out; nil = no mic.
    var candles: Int?
    var id: Int { slot }
}

struct BlowReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var candleCount: Int
    var results: [BlowResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Hum It

struct HumTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// The reference note to hum, in Hz.
    var targetHz: Double
    var listenSeconds: Double
    var humSeconds: Double

    /// Humming begins after the note has played.
    var humStart: Date { startAt.addingTimeInterval(listenSeconds) }
    var deadline: Date { humStart.addingTimeInterval(humSeconds) }
}

struct HumResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Pitch error in cents (100 = a semitone); nil = never hummed.
    var errorCents: Int?
    var id: Int { slot }
}

struct HumReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [HumResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Crack the Safe

struct SafeTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// The combination every device must dial in, e.g. [4, 9, 1].
    var combo: [Int]
    var maxSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(maxSeconds) }
}

struct SafeResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Time to crack the safe in ms; nil = never opened it in time.
    var elapsedMs: Int?
    var id: Int { slot }
}

struct SafeReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var combo: [Int]
    var results: [SafeResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Feel the Beat

struct BeatTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    /// Gaps between successive beats, in ms (one fewer than the beat count).
    var gaps: [Int]
    var leadSeconds: Double
    var tapSeconds: Double

    /// The pattern plays first; tapping is scored once it has finished.
    var patternMs: Int { gaps.reduce(0, +) }
    var tapStart: Date { startAt.addingTimeInterval(leadSeconds + Double(patternMs) / 1000) }
    var deadline: Date { tapStart.addingTimeInterval(tapSeconds) }
}

struct BeatResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Mean per-gap timing error in ms; nil = didn't tap the pattern back.
    var errorMs: Int?
    var id: Int { slot }
}

struct BeatReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [BeatResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Colour Clash

/// The Stroop game: a colour name printed in a clashing ink. The prompt
/// sequence is regenerated identically on every device from the seed
/// (like Sort Circuit's tile layout); each device validates taps locally
/// and reports only its penalty-inclusive time, so the host scores it
/// latency-free.
struct ClashTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    var seed: UInt64
    var promptCount: Int
    var maxSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(maxSeconds) }
}

struct ClashResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// Penalty-inclusive; nil = never finished.
    var elapsedMs: Int?
    var mistakes: Int
    var id: Int { slot }
}

struct ClashReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [ClashResult]
    var winners: [Int]
    var points: [Int: Int]
    var roundWinners: [Int]
    var nextAt: Date?
}

// MARK: - Tap Frenzy

struct FrenzyTurn: Codable, Hashable {
    var round: Int
    var turn: Int
    var points: [Int: Int]
    var startAt: Date
    var tapSeconds: Double

    var deadline: Date { startAt.addingTimeInterval(tapSeconds) }
}

struct FrenzyResult: Codable, Hashable, Identifiable {
    var slot: Int
    /// nil = never tapped at all.
    var taps: Int?
    var id: Int { slot }
}

struct FrenzyReveal: Codable, Hashable {
    var round: Int
    var turn: Int
    var results: [FrenzyResult]
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

    /// A rematch invite parked at a well-known ID (besides riding the old
    /// stream), so devices that weren't in the game when "Play again" was
    /// tapped can discover it with a single fetch from the home screen.
    static func rematch(_ gameID: String) -> String {
        "g\(gameID)-rematch"
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

    static func clockTap(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-k\(turn)-clk\(slot)"
    }

    static func dice(_ gameID: String, round: Int, run: Int, step: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-u\(run)-d\(step)-pl\(slot)"
    }

    static func goldPick(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-au\(turn)-gld\(slot)"
    }

    static func eyeball(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-eb\(turn)-eye\(slot)"
    }

    static func circleDraw(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-pc\(turn)-cir\(slot)"
    }

    static func sortTime(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-sc\(turn)-srt\(slot)"
    }

    static func steadyTime(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-sh\(turn)-std\(slot)"
    }

    static func showdownThrow(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-sd\(turn)-rps\(slot)"
    }

    static func frenzyTaps(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-tf\(turn)-frz\(slot)"
    }

    static func globeGuess(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-gt\(turn)-glb\(slot)"
    }

    static func clashTime(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-cc\(turn)-clc\(slot)"
    }

    static func levelError(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-sl\(turn)-lvl\(slot)"
    }

    static func pourFill(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-po\(turn)-pur\(slot)"
    }

    static func mazeTime(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-mz\(turn)-maz\(slot)"
    }

    static func loudLevel(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-ld\(turn)-lod\(slot)"
    }

    static func blowCandles(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-bl\(turn)-blw\(slot)"
    }

    static func humPitch(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-hm\(turn)-hum\(slot)"
    }

    static func safeTime(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-sf\(turn)-saf\(slot)"
    }

    static func beatError(_ gameID: String, round: Int, turn: Int, slot: Int) -> String {
        "g\(gameID)-r\(round)-bt\(turn)-bet\(slot)"
    }
}
