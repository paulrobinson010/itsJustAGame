import SwiftUI

/// A transport that goes nowhere — the screenshot tour plays entirely
/// offline.
struct NullTransport: GameTransport {
    func put(id: String, body: Data) async throws {}
    func get(ids: [String]) async throws -> [String: Data] { [:] }
}

/// Fabricated mid-game data for App Store screenshots: Mum, Dad, Freddy
/// and Lilly, deep in a best-of-3. Every phase struct is built at the
/// moment its step is shown so live countdowns sit mid-window.
enum Demo {
    static let players = [
        PlayerInfo(slot: 1, name: "Mum", colorIndex: 0),
        PlayerInfo(slot: 2, name: "Dad", colorIndex: 1),
        PlayerInfo(slot: 3, name: "Freddy", colorIndex: 2),
        PlayerInfo(slot: 4, name: "Lilly", colorIndex: 3),
    ]

    static let config = GameConfig(
        gameID: "demo",
        roundsToWin: 3,
        players: players,
        createdAt: Date()
    )

    @MainActor
    static func makeSession() -> GameSession {
        let saved = SavedGame(
            gameID: "demo",
            keyBase64URL: GameCrypto().base64URL,
            mySlot: 1,
            isHost: true,
            hostConfig: config,
            title: "Demo",
            createdAt: Date()
        )
        return GameSession(saved: saved, transport: NullTransport(), crypto: GameCrypto())
    }

    @MainActor
    static func makeEngine() -> HostEngine {
        let engine = HostEngine(config: config, transport: NullTransport(), crypto: GameCrypto())
        engine.applyDemoJoined([1, 2, 3, 4])
        return engine
    }

    struct Step {
        var points: [Int: Int] = [:]
        var roundsWon: [Int: Int] = [1: 1, 2: 1, 3: 1]
        var duration: Double = 2.0
        let make: () -> GamePhase
    }

    private static func now(_ offset: Double) -> Date {
        Date().addingTimeInterval(offset)
    }

    /// A believable hand-drawn circle: base ring plus low-frequency wobble.
    private static func demoCircle(wobble: Double, phase: Double, gap: Double) -> [Double] {
        var flat: [Double] = []
        let count = 90
        for index in 0..<count {
            let t = Double(index) / Double(count - 1) * 2 * .pi * (1 - gap)
            let radius = 0.34 * (1 + wobble * sin(3 * t + phase) + wobble * 0.6 * sin(7 * t))
            flat.append(0.5 + cos(t) * radius)
            flat.append(0.5 + sin(t) * radius)
        }
        return flat
    }

    private static let goldBoard = [
        2, 1, 4, 3, 2,
        3, 6, 2, 8, 1,
        1, 4, 10, 5, 3,
        5, 2, 4, 1, 6,
        2, 3, 1, 5, 4,
    ]

    static let steps: [Step] = [
        // Core flow
        Step { .lobby(joined: [1, 2, 3, 4]) },
        Step(points: [:]) { .wheel(round: 2, chooser: 3, spinSeconds: 5) },
        Step { .wheel(round: 2, chooser: 1, spinSeconds: 5) },
        Step { .roundIntro(round: 2, game: .senseOfDirection) },

        // Sense of Direction
        Step(points: [2: 2, 1: 1]) {
            .turn(TurnStart(
                round: 2, turn: 3,
                target: TargetLocation(name: "Eiffel Tower, Paris", coordinate: Coordinate(latitude: 48.8584, longitude: 2.2945)),
                startAt: now(-6), introSeconds: 4, aimSeconds: 15
            ))
        },
        Step(points: [2: 2, 1: 1]) {
            .reveal(TurnReveal(
                round: 2, turn: 3,
                target: TargetLocation(name: "Eiffel Tower, Paris", coordinate: Coordinate(latitude: 48.8584, longitude: 2.2945)),
                outcomes: [
                    PlayerOutcome(slot: 1, bearing: 151, correctBearing: 149.2, errorDegrees: 1.8, coordinate: Coordinate(latitude: 51.507, longitude: -0.128)),
                    PlayerOutcome(slot: 2, bearing: 144, correctBearing: 149.1, errorDegrees: 5.1, coordinate: Coordinate(latitude: 51.512, longitude: -0.121)),
                    PlayerOutcome(slot: 3, bearing: 163, correctBearing: 149.3, errorDegrees: 13.7, coordinate: Coordinate(latitude: 51.503, longitude: -0.135)),
                    PlayerOutcome(slot: 4, bearing: 97, correctBearing: 149.0, errorDegrees: 52.0, coordinate: Coordinate(latitude: 51.509, longitude: -0.116)),
                ],
                winner: 1, points: [1: 2, 2: 2], roundWinner: nil, nextTurnAt: now(10)
            ))
        },

        // Hide & Seek
        Step { .hiding(HideStart(round: 2, gridSize: 5, startAt: now(-4), hideSeconds: 15)) },
        Step {
            .seekTurn(SeekTurnStart(
                round: 2, turn: 4, seeker: 3, order: [3, 1, 4, 2], gridSize: 5,
                startAt: now(-3), seekSeconds: 15,
                searched: [0, 7, 12, 18], found: [4: 12]
            ))
        },
        Step {
            .seekReveal(SeekReveal(
                round: 2, turn: 4, seeker: 3, cell: 6, gridSize: 5,
                revealed: [2], searched: [0, 6, 7, 12, 18], found: [2: 6, 4: 12],
                remainingHidden: [1, 3], roundWinners: [], nextTurnAt: now(6)
            ))
        },

        // Higher or Lower
        Step(points: [1: 1, 3: 1]) {
            .cardGuess(CardTurn(
                round: 2, match: 2, step: 3,
                card: PlayingCard(rank: 7, suit: .hearts),
                alive: [1, 2, 3], points: [1: 1, 3: 1],
                startAt: now(-2), guessSeconds: 10
            ))
        },
        Step(points: [1: 1, 3: 1]) {
            .cardReveal(CardReveal(
                round: 2, match: 2, step: 3,
                previousCard: PlayingCard(rank: 7, suit: .hearts),
                nextCard: PlayingCard(rank: 12, suit: .spades),
                guesses: [1: .higher, 2: .lower, 3: .higher],
                eliminated: [2], alive: [1, 3], isTie: false,
                matchWinners: [], points: [1: 1, 3: 1], roundWinners: [], nextAt: now(7)
            ))
        },

        // Repeat After Me
        Step(points: [4: 2, 1: 1]) {
            .sequenceTurn(SequenceTurn(
                round: 2, match: 3, step: 3,
                sequence: [0, 2, 1, 3, 2],
                alive: [1, 2, 4], points: [4: 2, 1: 1],
                startAt: now(-6), watchSeconds: 4.75, answerSeconds: 8
            ))
        },
        Step(points: [4: 2, 1: 1]) {
            .sequenceReveal(SequenceReveal(
                round: 2, match: 3, step: 3,
                sequence: [0, 2, 1, 3, 2],
                results: [
                    SequencePlayerResult(slot: 1, taps: [0, 2, 1, 3, 2], correct: true),
                    SequencePlayerResult(slot: 2, taps: [0, 2, 3], correct: false),
                    SequencePlayerResult(slot: 4, taps: [0, 2, 1, 3, 2], correct: true),
                ],
                eliminated: [2], alive: [1, 4], matchWinners: [],
                points: [4: 2, 1: 1], roundWinners: [], nextAt: now(6)
            ))
        },

        // Lightning
        Step(points: [2: 2, 4: 1]) {
            .flashTurn(FlashTurn(
                round: 2, turn: 3, points: [2: 2, 4: 1],
                startAt: now(-2), flashAt: now(-1), tapWindowSeconds: 4
            ))
        },
        Step(points: [2: 2, 4: 1]) {
            .flashReveal(FlashReveal(
                round: 2, turn: 3,
                results: [
                    FlashResult(slot: 1, elapsedMs: 243, falseStart: false),
                    FlashResult(slot: 2, elapsedMs: 312, falseStart: false),
                    FlashResult(slot: 3, elapsedMs: nil, falseStart: true),
                    FlashResult(slot: 4, elapsedMs: 401, falseStart: false),
                ],
                winners: [1], points: [1: 1, 2: 2, 4: 1], roundWinners: [], nextAt: now(6)
            ))
        },

        // Put Your Finger On It
        Step(points: [3: 1]) {
            .fingerTurn(FingerTurn(
                round: 2, turn: 2, regionName: "Europe",
                regionCenter: Coordinate(latitude: 53, longitude: 12),
                regionSpanLat: 30, regionSpanLon: 44,
                placeName: "France", points: [3: 1],
                startAt: now(-3), guessSeconds: 15
            ))
        },
        Step(points: [3: 1]) {
            .fingerReveal(FingerReveal(
                round: 2, turn: 2, regionName: "Europe",
                placeName: "France", capitalName: "Paris",
                target: Coordinate(latitude: 48.8566, longitude: 2.3522),
                outcomes: [
                    FingerOutcome(slot: 1, coordinate: Coordinate(latitude: 45.7, longitude: 4.8), distanceKm: 392),
                    FingerOutcome(slot: 2, coordinate: Coordinate(latitude: 50.8, longitude: 4.4), distanceKm: 264),
                    FingerOutcome(slot: 3, coordinate: Coordinate(latitude: 48.5, longitude: 2.6), distanceKm: 44),
                    FingerOutcome(slot: 4, coordinate: Coordinate(latitude: 40.4, longitude: -3.7), distanceKm: 1053),
                ],
                winners: [3], points: [3: 2], roundWinners: [], nextAt: now(7)
            ))
        },

        // Ten Seconds
        Step(points: [2: 1, 1: 1]) {
            .clockTurn(ClockTurn(
                round: 2, turn: 3, points: [2: 1, 1: 1],
                startAt: now(-5), targetSeconds: 12, visibleSeconds: 3, maxSeconds: 20
            ))
        },
        Step(points: [2: 1, 1: 1]) {
            .clockReveal(ClockReveal(
                round: 2, turn: 3, targetSeconds: 12,
                results: [
                    ClockResult(slot: 1, elapsedMs: 12430, errorMs: 430),
                    ClockResult(slot: 2, elapsedMs: 11870, errorMs: 130),
                    ClockResult(slot: 3, elapsedMs: 9100, errorMs: 2900),
                    ClockResult(slot: 4, elapsedMs: 15850, errorMs: 3850),
                ],
                winners: [2], points: [2: 2, 1: 1], roundWinners: [], nextAt: now(6)
            ))
        },

        // Push Your Luck
        Step {
            .diceStep(DiceStep(
                round: 2, run: 2, step: 3, pot: 14,
                riders: [1, 3], banks: [2: 9, 4: 6],
                startAt: now(-2), chooseSeconds: 8
            ))
        },
        Step {
            .diceReveal(DiceReveal(
                round: 2, run: 2, step: 3,
                die: nil, isSkull: true, wheelIndex: 2, spinSeconds: 3,
                potBefore: 14, potAfter: 0,
                choices: [1: true, 3: true], bankedNow: [], riders: [],
                banks: [2: 9, 4: 6], runOver: true, roundWinners: [], nextAt: now(7)
            ))
        },

        // Gold Rush
        Step {
            .goldTurn(GoldTurn(
                round: 2, turn: 3, gridSize: 5, coins: goldBoard,
                totals: [2: 12, 1: 8, 3: 5],
                startAt: now(-3), pickSeconds: 12
            ))
        },
        Step {
            .goldReveal(GoldReveal(
                round: 2, turn: 3, gridSize: 5, coins: goldBoard,
                picks: [1: 8, 2: 12, 3: 12, 4: 15],
                clashes: [12],
                gains: [1: 8, 4: 5],
                totals: [1: 16, 2: 12, 3: 5, 4: 5],
                roundWinners: [], nextAt: now(7)
            ))
        },

        // Eyeball It — dots visible, then the guess controls
        Step(points: [1: 1, 4: 1], duration: 2.6) {
            .eyeballTurn(EyeballTurn(
                round: 2, turn: 2, points: [1: 1, 4: 1],
                startAt: now(0.2), count: 96, seed: 424_242,
                visibleSeconds: 2.5, guessSeconds: 12
            ))
        },
        Step(points: [1: 1, 4: 1]) {
            .eyeballTurn(EyeballTurn(
                round: 2, turn: 2, points: [1: 1, 4: 1],
                startAt: now(-6), count: 96, seed: 424_242,
                visibleSeconds: 2, guessSeconds: 12
            ))
        },
        Step(points: [1: 1, 4: 1]) {
            .eyeballReveal(EyeballReveal(
                round: 2, turn: 2, count: 96,
                results: [
                    EyeballResult(slot: 1, guess: 88, error: 8),
                    EyeballResult(slot: 2, guess: 120, error: 24),
                    EyeballResult(slot: 3, guess: 75, error: 21),
                    EyeballResult(slot: 4, guess: 102, error: 6),
                ],
                winners: [4], points: [1: 1, 4: 2], roundWinners: [], nextAt: now(6)
            ))
        },

        // Perfect Circle
        Step(points: [3: 2]) {
            .circleTurn(CircleTurn(round: 2, turn: 2, points: [3: 2], startAt: now(-2), drawSeconds: 10))
        },
        Step(points: [3: 2], duration: 3.0) {
            .circleReveal({
                let paths = [
                    (slot: 1, flat: demoCircle(wobble: 0.05, phase: 0.4, gap: 0.02)),
                    (slot: 2, flat: demoCircle(wobble: 0.16, phase: 2.1, gap: 0.06)),
                    (slot: 3, flat: demoCircle(wobble: 0.02, phase: 1.2, gap: 0.01)),
                    (slot: 4, flat: demoCircle(wobble: 0.24, phase: 4.0, gap: 0.12)),
                ]
                let results = paths.map { entry in
                    CircleResult(slot: entry.slot, score: CircleScore.evaluate(flat: entry.flat), path: entry.flat)
                }
                return CircleReveal(
                    round: 2, turn: 2, results: results,
                    winners: [3], points: [3: 3], roundWinners: [3], nextAt: nil
                )
            }())
        },

        // Sort Circuit
        Step(points: [2: 1, 3: 1]) {
            .sortTurn(SortTurn(
                round: 2, turn: 2, points: [2: 1, 3: 1],
                startAt: now(-1.2), seed: 77, tileCount: 9, maxSeconds: 30
            ))
        },
        Step(points: [2: 1, 3: 1]) {
            .sortReveal(SortReveal(
                round: 2, turn: 2,
                results: [
                    SortResult(slot: 1, elapsedMs: 7420, mistakes: 0),
                    SortResult(slot: 2, elapsedMs: 9870, mistakes: 2),
                    SortResult(slot: 3, elapsedMs: 6980, mistakes: 0),
                    SortResult(slot: 4, elapsedMs: nil, mistakes: 1),
                ],
                winners: [3], points: [2: 1, 3: 2], roundWinners: [], nextAt: now(6)
            ))
        },

        // Steady Hand — mid-run, ring drifting
        Step(points: [1: 1, 2: 1], duration: 2.6) {
            .steadyTurn(SteadyTurn(
                round: 2, turn: 2, points: [1: 1, 2: 1],
                startAt: now(-9), seed: 909_909, maxSeconds: 40
            ))
        },
        Step(points: [1: 1, 2: 1]) {
            .steadyReveal(SteadyReveal(
                round: 2, turn: 2,
                results: [
                    SteadyResult(slot: 1, survivedMs: 21_340),
                    SteadyResult(slot: 2, survivedMs: 26_910),
                    SteadyResult(slot: 3, survivedMs: 14_270),
                    SteadyResult(slot: 4, survivedMs: 8_450),
                ],
                winners: [2], points: [1: 1, 2: 2], roundWinners: [], nextAt: now(6)
            ))
        },

        // Showdown
        Step {
            .showdownTurn(ShowdownTurn(
                round: 2, turn: 3, totals: [2: 3, 1: 2, 4: 1],
                startAt: now(-2), throwSeconds: 8
            ))
        },
        Step {
            .showdownReveal(ShowdownReveal(
                round: 2, turn: 3,
                thrown: [1: .rock, 2: .paper, 3: .scissors, 4: .rock],
                gains: [1: 1, 2: 2, 3: 1, 4: 1],
                totals: [1: 3, 2: 5, 3: 1, 4: 2],
                winners: [2], roundWinners: [2], nextAt: nil
            ))
        },

        // Tap Frenzy — mid-mash
        Step(points: [4: 2, 3: 1]) {
            .frenzyTurn(FrenzyTurn(
                round: 2, turn: 3, points: [4: 2, 3: 1],
                startAt: now(-2), tapSeconds: 5
            ))
        },
        Step(points: [4: 2, 3: 1]) {
            .frenzyReveal(FrenzyReveal(
                round: 2, turn: 3,
                results: [
                    FrenzyResult(slot: 1, taps: 31),
                    FrenzyResult(slot: 2, taps: 27),
                    FrenzyResult(slot: 3, taps: 38),
                    FrenzyResult(slot: 4, taps: 43),
                ],
                winners: [4], points: [3: 1, 4: 3], roundWinners: [4], nextAt: nil
            ))
        },

        // Globetrotter
        Step(points: [2: 1, 4: 1]) {
            .globeTurn(GlobeTurn(
                round: 2, turn: 3, landmark: "Taj Mahal", continent: "Asia",
                points: [2: 1, 4: 1], startAt: now(-3), guessSeconds: 15
            ))
        },
        Step(points: [2: 1, 4: 1]) {
            .globeReveal(GlobeReveal(
                round: 2, turn: 3, landmark: "Taj Mahal", country: "India",
                target: Coordinate(latitude: 27.1751, longitude: 78.0421),
                outcomes: [
                    FingerOutcome(slot: 1, coordinate: Coordinate(latitude: 31.0, longitude: 71.0), distanceKm: 940),
                    FingerOutcome(slot: 2, coordinate: Coordinate(latitude: 26.2, longitude: 80.3), distanceKm: 250),
                    FingerOutcome(slot: 3, coordinate: Coordinate(latitude: 15.0, longitude: 74.0), distanceKm: 1400),
                    FingerOutcome(slot: 4, coordinate: Coordinate(latitude: 28.6, longitude: 77.2), distanceKm: 180),
                ],
                winners: [4], points: [2: 1, 4: 2], roundWinners: [], nextAt: now(8)
            ))
        },

        // Colour Clash — mid-run
        Step(points: [1: 1, 2: 1]) {
            .clashTurn(ClashTurn(
                round: 2, turn: 2, points: [1: 1, 2: 1],
                startAt: now(-4), seed: 5150, promptCount: 8, maxSeconds: 20
            ))
        },
        Step(points: [1: 1, 2: 1]) {
            .clashReveal(ClashReveal(
                round: 2, turn: 2,
                results: [
                    ClashResult(slot: 1, elapsedMs: 6120, mistakes: 0),
                    ClashResult(slot: 2, elapsedMs: 5480, mistakes: 1),
                    ClashResult(slot: 3, elapsedMs: 8300, mistakes: 2),
                    ClashResult(slot: 4, elapsedMs: 7010, mistakes: 0),
                ],
                winners: [2], points: [1: 1, 2: 2], roundWinners: [], nextAt: now(6)
            ))
        },

        // Spirit Level — reveal (turn needs a real device)
        Step(points: [3: 1, 1: 1]) {
            .levelReveal(LevelReveal(
                round: 2, turn: 2, targetDegrees: 22,
                results: [
                    LevelResult(slot: 1, errorMilliDeg: 2100),
                    LevelResult(slot: 2, errorMilliDeg: 7400),
                    LevelResult(slot: 3, errorMilliDeg: 900),
                    LevelResult(slot: 4, errorMilliDeg: 4300),
                ],
                winners: [3], points: [3: 2, 1: 1], roundWinners: [], nextAt: now(7)
            ))
        },

        // Pour It — reveal
        Step(points: [2: 1, 4: 1]) {
            .pourReveal(PourReveal(
                round: 2, turn: 2, targetPercent: 72,
                results: [
                    PourResult(slot: 1, fillPercent: 64, overflowed: false),
                    PourResult(slot: 2, fillPercent: 70, overflowed: false),
                    PourResult(slot: 3, fillPercent: 100, overflowed: true),
                    PourResult(slot: 4, fillPercent: 78, overflowed: false),
                ],
                winners: [2], points: [2: 2, 4: 1], roundWinners: [], nextAt: now(7)
            ))
        },

        // Marble Maze — the maze renders even without motion
        Step(points: [2: 1, 3: 1], duration: 2.6) {
            .mazeTurn(MazeTurn(
                round: 2, turn: 2, points: [2: 1, 3: 1],
                startAt: now(-3), seed: 24_601, size: 6, maxSeconds: 45
            ))
        },
        Step(points: [2: 1, 3: 1]) {
            .mazeReveal(MazeReveal(
                round: 2, turn: 2,
                results: [
                    MazeResult(slot: 1, elapsedMs: 18_400),
                    MazeResult(slot: 2, elapsedMs: 12_900),
                    MazeResult(slot: 3, elapsedMs: 15_700),
                    MazeResult(slot: 4, elapsedMs: nil),
                ],
                winners: [2], points: [2: 2, 3: 1], roundWinners: [], nextAt: now(6)
            ))
        },

        // Loudest — reveal
        Step(points: [4: 1, 1: 1]) {
            .loudReveal(LoudReveal(
                round: 2, turn: 2,
                results: [
                    LoudResult(slot: 1, level: 720),
                    LoudResult(slot: 2, level: 610),
                    LoudResult(slot: 3, level: 540),
                    LoudResult(slot: 4, level: 880),
                ],
                winners: [4], points: [4: 2, 1: 1], roundWinners: [], nextAt: now(6)
            ))
        },

        // Blow It Out — reveal
        Step(points: [2: 1, 3: 1]) {
            .blowReveal(BlowReveal(
                round: 2, turn: 2, candleCount: 10,
                results: [
                    BlowResult(slot: 1, candles: 6),
                    BlowResult(slot: 2, candles: 9),
                    BlowResult(slot: 3, candles: 4),
                    BlowResult(slot: 4, candles: 7),
                ],
                winners: [2], points: [2: 2, 3: 1], roundWinners: [], nextAt: now(6)
            ))
        },

        // Hum It — reveal
        Step(points: [1: 1, 3: 1]) {
            .humReveal(HumReveal(
                round: 2, turn: 2,
                results: [
                    HumResult(slot: 1, errorCents: 22),
                    HumResult(slot: 2, errorCents: 140),
                    HumResult(slot: 3, errorCents: 8),
                    HumResult(slot: 4, errorCents: 65),
                ],
                winners: [3], points: [1: 1, 3: 2], roundWinners: [], nextAt: now(7)
            ))
        },

        // Endings
        Step(roundsWon: [3: 2, 1: 1, 2: 1]) { .roundEnd(round: 2, winners: [3]) },
        Step(roundsWon: [1: 3, 3: 3, 2: 1]) { .tieBreak(candidates: [1, 3], winner: 3, spinSeconds: 4) },
        Step(roundsWon: [3: 3, 1: 2, 2: 1]) { .gameEnd(winner: 3) },
    ]
}

/// Steps through every screen with fabricated mid-game data so App Store
/// screenshots can be grabbed. No visible chrome: auto-advances on a
/// timer; tap pauses, swipe left/right steps, long-press exits.
struct DemoTourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var session = Demo.makeSession()
    @State private var engine = Demo.makeEngine()
    @State private var index = 0
    @State private var paused = false
    @State private var stepStarted = Date()

    var body: some View {
        ZStack {
            phaseContent
                // Fresh view state per step, so e.g. the wheel re-parks on
                // the new chooser instead of reusing the previous spin.
                .id(index)
                .frame(maxWidth: 700)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .overlay {
            // Invisible gesture layer so screenshots stay clean.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { paused.toggle() }
                .onLongPressGesture(minimumDuration: 0.8) { dismiss() }
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        if value.translation.width < 0 { advance() } else { back() }
                    }
                )
        }
        .task { await run() }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch session.phase {
        case .lobby(let joined):
            LobbyView(session: session, engine: engine, joined: joined)
        case .wheel(let round, let chooser, let spinSeconds):
            WheelPhaseView(session: session, round: round, chooser: chooser, spinSeconds: spinSeconds)
        case .roundIntro(let round, let game):
            RoundIntroView(round: round, game: game)
        case .turn(let turnStart):
            DirectionTurnView(session: session, turnStart: turnStart)
        case .reveal(let reveal):
            RevealView(session: session, reveal: reveal)
        case .hiding(let hideStart):
            HideView(session: session, hideStart: hideStart)
        case .seekTurn(let turnStart):
            SeekTurnView(session: session, turnStart: turnStart)
        case .seekReveal(let reveal):
            SeekRevealView(session: session, reveal: reveal)
        case .cardGuess(let turn):
            CardGuessView(session: session, turn: turn)
        case .cardReveal(let reveal):
            CardRevealView(session: session, reveal: reveal)
        case .sequenceTurn(let turn):
            SequenceTurnView(session: session, turn: turn)
        case .sequenceReveal(let reveal):
            SequenceRevealView(session: session, reveal: reveal)
        case .flashTurn(let turn):
            FlashTurnView(session: session, turn: turn)
        case .flashReveal(let reveal):
            FlashRevealView(session: session, reveal: reveal)
        case .fingerTurn(let turn):
            FingerTurnView(session: session, turn: turn)
        case .fingerReveal(let reveal):
            FingerRevealView(session: session, reveal: reveal)
        case .clockTurn(let turn):
            ClockTurnView(session: session, turn: turn)
        case .clockReveal(let reveal):
            ClockRevealView(session: session, reveal: reveal)
        case .diceStep(let step):
            DiceStepView(session: session, step: step)
        case .diceReveal(let reveal):
            DiceRevealView(session: session, reveal: reveal)
        case .goldTurn(let turn):
            GoldTurnView(session: session, turn: turn)
        case .goldReveal(let reveal):
            GoldRevealView(session: session, reveal: reveal)
        case .eyeballTurn(let turn):
            EyeballTurnView(session: session, turn: turn)
        case .eyeballReveal(let reveal):
            EyeballRevealView(session: session, reveal: reveal)
        case .circleTurn(let turn):
            CircleTurnView(session: session, turn: turn)
        case .circleReveal(let reveal):
            CircleRevealView(session: session, reveal: reveal)
        case .sortTurn(let turn):
            SortTurnView(session: session, turn: turn)
        case .sortReveal(let reveal):
            SortRevealView(session: session, reveal: reveal)
        case .steadyTurn(let turn):
            SteadyTurnView(session: session, turn: turn)
        case .steadyReveal(let reveal):
            SteadyRevealView(session: session, reveal: reveal)
        case .showdownTurn(let turn):
            ShowdownTurnView(session: session, turn: turn)
        case .showdownReveal(let reveal):
            ShowdownRevealView(session: session, reveal: reveal)
        case .frenzyTurn(let turn):
            FrenzyTurnView(session: session, turn: turn)
        case .frenzyReveal(let reveal):
            FrenzyRevealView(session: session, reveal: reveal)
        case .globeTurn(let turn):
            GlobeTurnView(session: session, turn: turn)
        case .globeReveal(let reveal):
            GlobeRevealView(session: session, reveal: reveal)
        case .clashTurn(let turn):
            ClashTurnView(session: session, turn: turn)
        case .clashReveal(let reveal):
            ClashRevealView(session: session, reveal: reveal)
        case .levelTurn(let turn):
            LevelTurnView(session: session, turn: turn)
        case .levelReveal(let reveal):
            LevelRevealView(session: session, reveal: reveal)
        case .pourTurn(let turn):
            PourTurnView(session: session, turn: turn)
        case .pourReveal(let reveal):
            PourRevealView(session: session, reveal: reveal)
        case .mazeTurn(let turn):
            MazeTurnView(session: session, turn: turn)
        case .mazeReveal(let reveal):
            MazeRevealView(session: session, reveal: reveal)
        case .loudTurn(let turn):
            LoudTurnView(session: session, turn: turn)
        case .loudReveal(let reveal):
            LoudRevealView(session: session, reveal: reveal)
        case .blowTurn(let turn):
            BlowTurnView(session: session, turn: turn)
        case .blowReveal(let reveal):
            BlowRevealView(session: session, reveal: reveal)
        case .humTurn(let turn):
            HumTurnView(session: session, turn: turn)
        case .humReveal(let reveal):
            HumRevealView(session: session, reveal: reveal)
        case .roundEnd(let round, let winners):
            RoundEndView(session: session, round: round, winners: winners)
        case .tieBreak(let candidates, let winner, let spinSeconds):
            TieBreakView(session: session, candidates: candidates, winner: winner, spinSeconds: spinSeconds)
        case .gameEnd(let winner):
            GameEndView(session: session, winner: winner, onClose: {}, onHostRematch: {})
        }
    }

    private func run() async {
        applyCurrent()
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(0.1))
            if paused {
                stepStarted = Date()
                continue
            }
            if Date().timeIntervalSince(stepStarted) >= Demo.steps[index].duration {
                advance()
            }
        }
    }

    private func advance() {
        index = (index + 1) % Demo.steps.count
        applyCurrent()
    }

    private func back() {
        index = (index - 1 + Demo.steps.count) % Demo.steps.count
        applyCurrent()
    }

    private func applyCurrent() {
        let step = Demo.steps[index]
        stepStarted = Date()
        session.applyDemoState(
            config: Demo.config,
            points: step.points,
            roundsWon: step.roundsWon,
            joined: [1, 2, 3, 4],
            phase: step.make()
        )
    }
}
