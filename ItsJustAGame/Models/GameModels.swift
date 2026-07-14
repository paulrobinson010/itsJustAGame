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
            return "Tilt to pour, and stop at the line without spilling. Closest to the target fill wins the point; first to \(GameTiming.pointsToWinRound) points wins the round."
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
    static let diceSpinMinSeconds: Double = 2.5
    static let diceSpinMaxSeconds: Double = 5

    // Gold Rush
    static let goldPickSeconds: Double = 12
    static let goldRevealSeconds: Double = 6
    static let goldTarget = 30
    static let goldMaxTurns = 15

    // Eyeball It
    static let eyeballVisibleSeconds: Double = 2
    static let eyeballGuessSeconds: Double = 12
    static let eyeballRevealSeconds: Double = 6
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
    static let circleRevealSeconds: Double = 8

    // Sort Circuit
    static let sortMaxSeconds: Double = 30
    static let sortPenaltyMs = 1000
    static let sortRevealSeconds: Double = 6

    // Steady Hand
    static let steadyMaxSeconds: Double = 40
    static let steadyRevealSeconds: Double = 6

    // Showdown
    static let showdownThrowSeconds: Double = 8
    static let showdownRevealSeconds: Double = 7
    static let showdownTarget = 5
    static let showdownMaxTurns = 12

    // Tap Frenzy
    static let frenzyTapSeconds: Double = 5
    static let frenzyRevealSeconds: Double = 6
    /// The biggest extra window Simplify can add, so the host waits for it.
    static let frenzyMaxAssistExtraSeconds: Double = 5

    // Globetrotter
    static let globeGuessSeconds: Double = 15
    static let globeRevealSeconds: Double = 9

    // Colour Clash
    static let clashPromptCount = 8
    static let clashPenaltyMs = 1000
    static let clashMaxSeconds: Double = 20
    static let clashRevealSeconds: Double = 6

    // Tilt games (Spirit Level, Pour It) share a device-local "get ready"
    // countdown before play begins — timed on each phone, not the host, so
    // a late-arriving turn still gives everyone the full run-up.
    static let tiltCountdownSeconds: Double = 5

    // Spirit Level — hold the bubble between the markers as long as you can.
    static let levelMaxSeconds: Double = 20
    /// Half-width of the "level" zone in degrees (the gap between the two
    /// markers is twice this). Simplify widens it on the assisted device.
    static let levelZoneDegrees: Double = 5
    static let levelRevealSeconds: Double = 7

    // Pour It
    static let pourSeconds: Double = 12
    static let pourRevealSeconds: Double = 7

    // Marble Maze
    static let mazeSize = 6
    static let mazeMaxSeconds: Double = 45
    static let mazeRevealSeconds: Double = 6

    // Loudest
    static let loudShoutSeconds: Double = 4
    static let loudRevealSeconds: Double = 6

    // Blow It Out
    static let blowSeconds: Double = 6
    static let blowCandles = 10
    static let blowRevealSeconds: Double = 6

    // Hum It
    static let humListenSeconds: Double = 2
    static let humSeconds: Double = 5
    static let humRevealSeconds: Double = 7

    // Crack the Safe
    static let safeDigits = 3
    static let safeMaxSeconds: Double = 30
    static let safeRevealSeconds: Double = 6

    // Feel the Beat
    static let beatCount = 4          // taps in the pattern (so 3 gaps)
    static let beatShortMs = 350      // the two possible gap lengths
    static let beatLongMs = 700
    static let beatListenLeadSeconds: Double = 1.5
    static let beatTapSeconds: Double = 8
    static let beatRevealSeconds: Double = 7
}
