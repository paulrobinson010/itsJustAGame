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

/// The version of the encrypted wire format (message shapes + game set).
/// Bump `current` whenever a change would stop an older build from
/// decoding the stream — new games, renamed/added message fields, etc.
/// A peer whose data omits the version (or is lower) is treated as that
/// older version; a peer whose version is *higher* than ours is one we may
/// not fully understand, so we tell the user to update.
enum AppProtocol {
    /// v0 = the 1.0 App Store release (before versioning existed).
    /// v1 = the 1.1 game set (Globetrotter, Colour Clash, the tilt/mic
    ///      games, Crack the Safe, Feel the Beat).
    static let current = 1
}

struct GameConfig: Codable, Hashable {
    var gameID: String
    var roundsToWin: Int
    var players: [PlayerInfo]
    var createdAt: Date
    /// The host's wire-format version. Optional so pre-1.1 configs (and any
    /// created by a 1.0 host) decode cleanly as version 0.
    var protocolVersion: Int?

    /// The host's wire version, with the pre-versioning default.
    var wireVersion: Int { protocolVersion ?? 0 }

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
    case steadyHand
    case showdown
    case tapFrenzy
    case globetrotter
    case colourClash
    case spiritLevel
    case pourIt
    case marbleMaze
    case loudest
    case blowItOut
    case humIt
    case crackTheSafe
    case feelTheBeat
    case sizeItUp
    case spotRecall
    case oddOneOut
    case traceIt
    case trafficLight

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
        case .steadyHand: return "Steady Hand"
        case .showdown: return "Showdown"
        case .tapFrenzy: return "Tap Frenzy"
        case .globetrotter: return "Globetrotter"
        case .colourClash: return "Colour Clash"
        case .spiritLevel: return "Spirit Level"
        case .pourIt: return "Pour It"
        case .marbleMaze: return "Marble Maze"
        case .loudest: return "Loudest"
        case .blowItOut: return "Blow It Out"
        case .humIt: return "Hum It"
        case .crackTheSafe: return "Crack the Safe"
        case .feelTheBeat: return "Feel the Beat"
        case .sizeItUp: return "Size It Up"
        case .spotRecall: return "Spot Recall"
        case .oddOneOut: return "Odd One Out"
        case .traceIt: return "Trace It"
        case .trafficLight: return "Traffic Light"
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
        case .steadyHand: return 2
        case .showdown: return 2
        case .tapFrenzy: return 2
        case .globetrotter: return 2
        case .colourClash: return 2
        case .spiritLevel: return 2
        case .pourIt: return 2
        case .marbleMaze: return 2
        case .loudest: return 2
        case .blowItOut: return 2
        case .humIt: return 2
        case .crackTheSafe: return 2
        case .feelTheBeat: return 2
        case .sizeItUp: return 2
        case .spotRecall: return 2
        case .oddOneOut: return 2
        case .traceIt: return 2
        case .trafficLight: return 2
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
        case .pushYourLuck: return "dial.medium.fill"
        case .goldRush: return "sparkles"
        case .eyeballIt: return "aqi.medium"
        case .perfectCircle: return "circle.dashed"
        case .sortCircuit: return "123.rectangle.fill"
        case .steadyHand: return "hand.raised.fill"
        case .showdown: return "scissors"
        case .tapFrenzy: return "hand.tap.fill"
        case .globetrotter: return "globe.europe.africa.fill"
        case .colourClash: return "paintpalette.fill"
        case .spiritLevel: return "gyroscope"
        case .pourIt: return "drop.fill"
        case .marbleMaze: return "square.grid.3x3.fill"
        case .loudest: return "speaker.wave.3.fill"
        case .blowItOut: return "wind"
        case .humIt: return "music.note"
        case .crackTheSafe: return "lock.rotation"
        case .feelTheBeat: return "waveform.path"
        case .sizeItUp: return "square.dashed"
        case .spotRecall: return "sparkle.magnifyingglass"
        case .oddOneOut: return "circle.grid.3x3.fill"
        case .traceIt: return "scribble.variable"
        case .trafficLight: return "trafficlight"
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
            return "The wheel grows the pot — five numbers, two 💀 busts. Ride the next spin or bank your share; a bust burns the pot, and reaching \(GameTiming.diceBankTarget) banks you automatically. First to bank \(GameTiming.diceBankTarget) wins the round."
        case .goldRush:
            return "Same board, one secret pick each. Alone on a square? Pocket its coins. Share it? Nobody scores. First to \(GameTiming.goldTarget) coins wins the round."
        case .eyeballIt:
            return "A cloud of dots flashes up, then vanishes. How many were there? Closest guess wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .perfectCircle:
            return "Draw the roundest circle you can — one finger, one stroke. Highest score wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .sortCircuit:
            return "Nine numbers scattered on screen. Tap 1 to 9 as fast as you can — mistakes cost a second. Fastest wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .steadyHand:
            return "Keep your finger inside the drifting, shrinking ring — slip out and you're done. Longest hold wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .showdown:
            return "Rock, paper, scissors — against the whole table at once. You score a win for every player you beat. First to \(GameTiming.showdownTarget) wins takes the round."
        case .tapFrenzy:
            return "\(Int(GameTiming.frenzyTapSeconds)) seconds. Tap as many times as you can. That's it. Most taps wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .globetrotter:
            return "A famous landmark, a world map, \(Int(GameTiming.globeGuessSeconds)) seconds. Drop your pin where on Earth you think it is — closest wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .colourClash:
            return "The name of a colour, printed in a different colour. Tap the colour it's PRINTED in — not the word — as fast as you can through them all. Fastest wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .spiritLevel:
            return "Tilt to keep the bubble between the two markers — but they drift faster and faster. The clock runs as long as you stay in. Longest hold wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .pourIt:
            return "Tip the phone either way to pour, and stop at the line without spilling. Closest to the target fill wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .marbleMaze:
            return "Tilt your phone to roll the ball through the maze to the exit. Fastest to escape wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .loudest:
            return "When it says GO, shout as loud as you can! Loudest wins the point; first to \(GameTiming.pointsToWinRound) points wins the round. (Nothing is recorded — just how loud you are.)"
        case .blowItOut:
            return "Blow at your phone to blow out the candles. Most candles out wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .humIt:
            return "Listen to the note, then hum it back. Closest to the pitch wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .crackTheSafe:
            return "Twist your phone like a safe dial to spin in the \(GameTiming.safeDigits)-digit combo. Fastest to crack it wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .feelTheBeat:
            return "Feel the rhythm buzz through your phone, then tap it straight back. Closest to the beat wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .sizeItUp:
            return "A shape flashes up, then vanishes. Draw it back at the same size from memory. Closest to the original size wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .spotRecall:
            return "A handful of dots flash on screen, then vanish. Tap where each one was. Closest to the real spots wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .oddOneOut:
            return "A grid of shapes, one a slightly different colour. Tap the odd one out as fast as you can — it gets harder each turn. Quickest wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .traceIt:
            return "A winding line appears. Trace along it with your finger as accurately as you can. Closest to the line wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
        case .trafficLight:
            return "Wait on red — tap the instant it turns green. Jump early and you're out for the turn. Fastest off the mark wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
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

    /// The lowest wire version that can run this game. The 1.1 games can't
    /// be decoded by a 1.0 build, so the host keeps them out of the menu
    /// whenever a 1.0 player is in the game.
    var minProtocolVersion: Int {
        switch self {
        case .globetrotter, .colourClash, .spiritLevel, .pourIt, .marbleMaze,
             .loudest, .blowItOut, .humIt, .crackTheSafe, .feelTheBeat,
             .sizeItUp, .spotRecall, .oddOneOut, .traceIt, .trafficLight:
            return 1
        default:
            return 0
        }
    }

    /// Games playable by a group whose lowest wire version is `version`
    /// (and that have enough players).
    static func available(for playerCount: Int, maxVersion: Int) -> [MiniGameType] {
        available(for: playerCount).filter { $0.minProtocolVersion <= maxVersion }
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
    /// A rematch found on the home screen that hasn't been accepted yet —
    /// shown as a request until the player taps to join.
    var rematchPending: Bool?
    /// Set for solo practice: the one game to play on repeat, over an
    /// in-memory transport. Practice games are never stored.
    var practiceGame: MiniGameType?

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
    /// Every turn begins with the same 3-2-1 "get ready" countdown, shown
    /// dead-centre over the game. Host turns are scheduled this far ahead so
    /// the shared overlay has a full run to count down.
    static let countdownSeconds: Double = 3
    /// Every results / reveal screen is shown for the same length.
    static let resultsSeconds: Double = 5

    /// The brief "here comes <game>" announcement before a round's first
    /// turn (the 3-2-1 countdown then runs before the turn itself).
    static let roundIntroSeconds: Double = 3
    static let introSeconds: Double = 4          // Sense of Direction's own reveal-the-place window
    static let aimSeconds: Double = 15
    static let revealSeconds: Double = 5
    static let betweenRoundsSeconds: Double = 5
    static let answerGraceSeconds: Double = 6
    static let pointsToWinRound = 3
    static let maxTurnsPerRound = 10
    /// A rematch auto-starts on its own, but only after everyone has been in
    /// the lobby together for this long — so a player who just tapped "join"
    /// actually sees the lobby and a beat to breathe before it kicks off,
    /// instead of the game snapping straight past them.
    static let rematchLobbyDwell: Double = 5

    // Hide & Seek
    static let hideSeconds: Double = 15
    static let seekSeconds: Double = 15
    static let seekRevealSeconds: Double = 5

    // Higher or Lower
    static let guessSeconds: Double = 10
    static let cardRevealSeconds: Double = 5

    // Repeat After Me
    static let sequenceStartLength = 3
    static let sequenceFlashSeconds: Double = 0.65
    static let sequenceRevealSeconds: Double = 5

    // Lightning
    static let flashWaitMinSeconds: Double = 2
    static let flashWaitMaxSeconds: Double = 7
    static let tapWindowSeconds: Double = 4
    static let flashRevealSeconds: Double = 5

    // Put Your Finger On It
    static let fingerGuessSeconds: Double = 15
    static let fingerRevealSeconds: Double = 5

    // Ten Seconds
    static let clockVisibleSeconds: Double = 3
    static let clockRevealSeconds: Double = 5

    // Push Your Luck
    static let diceChooseSeconds: Double = 8
    static let diceRevealSeconds: Double = 5
    static let diceBankTarget = 20
    static let diceMaxRuns = 12
    static let diceSpinMinSeconds: Double = 2.5
    static let diceSpinMaxSeconds: Double = 5

    // Gold Rush
    static let goldPickSeconds: Double = 12
    static let goldRevealSeconds: Double = 5
    static let goldTarget = 30
    static let goldMaxTurns = 15

    // Eyeball It
    static let eyeballVisibleSeconds: Double = 2
    static let eyeballGuessSeconds: Double = 12
    static let eyeballRevealSeconds: Double = 5
    static let eyeballMinCount = 15
    static let eyeballMaxCount = 250
    /// Consecutive clouds must differ by at least this many dots — uniform
    /// draws can land eerily close two turns running.
    static let eyeballMinStep = 40
    /// Slider headroom past the biggest possible cloud, so the true count
    /// is never sitting at the end stop.
    static let eyeballSliderMax = 275

    // Perfect Circle
    static let circleDrawSeconds: Double = 10
    static let circleRevealSeconds: Double = 5

    // Sort Circuit
    static let sortMaxSeconds: Double = 30
    static let sortPenaltyMs = 1000
    static let sortRevealSeconds: Double = 5

    // Steady Hand
    static let steadyMaxSeconds: Double = 40
    static let steadyRevealSeconds: Double = 5

    // Showdown
    static let showdownThrowSeconds: Double = 8
    static let showdownRevealSeconds: Double = 5
    static let showdownTarget = 5
    static let showdownMaxTurns = 12

    // Tap Frenzy
    static let frenzyTapSeconds: Double = 5
    static let frenzyRevealSeconds: Double = 5
    /// The biggest extra window Simplify can add, so the host waits for it.
    static let frenzyMaxAssistExtraSeconds: Double = 5

    // Globetrotter
    static let globeGuessSeconds: Double = 15
    static let globeRevealSeconds: Double = 5

    // Colour Clash
    static let clashPromptCount = 8
    static let clashPenaltyMs = 1000
    static let clashMaxSeconds: Double = 20
    static let clashRevealSeconds: Double = 5

    // Spirit Level — hold the bubble between the markers as long as you can.
    static let levelMaxSeconds: Double = 20
    /// Half-width of the "level" zone in degrees (the gap between the two
    /// markers is twice this). Simplify widens it on the assisted device.
    static let levelZoneDegrees: Double = 5
    static let levelRevealSeconds: Double = 5

    // Pour It
    static let pourSeconds: Double = 12
    static let pourRevealSeconds: Double = 5

    // Marble Maze
    static let mazeSize = 6
    static let mazeMaxSeconds: Double = 45
    static let mazeRevealSeconds: Double = 5

    // Loudest
    static let loudShoutSeconds: Double = 4
    static let loudRevealSeconds: Double = 5

    // Blow It Out
    static let blowSeconds: Double = 6
    static let blowCandles = 20
    static let blowRevealSeconds: Double = 5

    // Hum It
    static let humListenSeconds: Double = 2
    static let humSeconds: Double = 5
    static let humRevealSeconds: Double = 5

    // Crack the Safe
    static let safeDigits = 3
    static let safeMaxSeconds: Double = 30
    static let safeRevealSeconds: Double = 5

    // Feel the Beat
    static let beatCount = 4          // taps in the pattern (so 3 gaps)
    static let beatShortMs = 350      // the two possible gap lengths
    static let beatLongMs = 700
    static let beatListenLeadSeconds: Double = 1.5
    static let beatTapSeconds: Double = 8
    static let beatRevealSeconds: Double = 5

    // Size It Up
    static let sizeShowSeconds: Double = 2      // how long the shape flashes
    static let sizeDrawSeconds: Double = 10     // time to draw it back
    static let sizeRevealSeconds: Double = 5
    /// Target size range, as a fraction of the square canvas's side.
    static let sizeMinFraction: Double = 0.2
    static let sizeMaxFraction: Double = 0.85

    // Spot Recall
    static let spotDotCount = 4                 // dots to remember
    static let spotShowSeconds: Double = 2.5    // how long they flash
    static let spotRecallSeconds: Double = 12   // time to place your taps
    static let spotRevealSeconds: Double = 5

    // Odd One Out
    static let oddGridSize = 5                  // 5×5 grid of shapes
    static let oddMaxSeconds: Double = 15       // time to find it
    static let oddWrongPenaltyMs = 2000         // added per wrong tap
    static let oddRevealSeconds: Double = 5

    // Trace It
    static let traceSeconds: Double = 10        // time to trace the line
    static let traceRevealSeconds: Double = 5

    // Traffic Light
    static let trafficRedMinSeconds: Double = 2 // random red wait before green
    static let trafficRedMaxSeconds: Double = 7
    static let trafficTapSeconds: Double = 4    // window to react after green
    static let trafficRevealSeconds: Double = 5
}
