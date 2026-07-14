import Foundation
import Observation
import SwiftUI

enum GamePhase: Hashable {
    case lobby(joined: Set<Int>)
    case wheel(round: Int, chooser: Int, spinSeconds: Double, maxGameVersion: Int?)
    case roundIntro(round: Int, game: MiniGameType)
    // Sense of Direction
    case turn(TurnStart)
    case reveal(TurnReveal)
    // Hide & Seek
    case hiding(HideStart)
    case seekTurn(SeekTurnStart)
    case seekReveal(SeekReveal)
    // Higher or Lower
    case cardGuess(CardTurn)
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
    // Size It Up
    case sizeTurn(SizeTurn)
    case sizeReveal(SizeReveal)
    // Spot Recall
    case spotTurn(SpotTurn)
    case spotReveal(SpotReveal)
    // Odd One Out
    case oddTurn(OddTurn)
    case oddReveal(OddReveal)
    // Trace It
    case traceTurn(TraceTurn)
    case traceReveal(TraceReveal)
    // Traffic Light
    case trafficTurn(TrafficTurn)
    case trafficReveal(TrafficReveal)
    case roundEnd(round: Int, winners: [Int])
    case tieBreak(candidates: [Int], winner: Int, spinSeconds: Double)
    case gameEnd(winner: Int)

    /// When this phase's play begins, if it's a turn with a scheduled start.
    /// The shared 3-2-1 countdown overlay runs from here backwards; reveals,
    /// the lobby, the wheel and the endings return nil (no countdown).
    var turnStartAt: Date? {
        switch self {
        case .turn(let t): return t.startAt
        case .hiding(let t): return t.startAt
        case .seekTurn(let t): return t.startAt
        case .cardGuess(let t): return t.startAt
        case .sequenceTurn(let t): return t.startAt
        case .flashTurn(let t): return t.startAt
        case .fingerTurn(let t): return t.startAt
        case .clockTurn(let t): return t.startAt
        case .diceStep(let t): return t.startAt
        case .goldTurn(let t): return t.startAt
        case .eyeballTurn(let t): return t.startAt
        case .circleTurn(let t): return t.startAt
        case .sortTurn(let t): return t.startAt
        case .steadyTurn(let t): return t.startAt
        case .showdownTurn(let t): return t.startAt
        case .frenzyTurn(let t): return t.startAt
        case .globeTurn(let t): return t.startAt
        case .clashTurn(let t): return t.startAt
        case .levelTurn(let t): return t.startAt
        case .pourTurn(let t): return t.startAt
        case .mazeTurn(let t): return t.startAt
        case .loudTurn(let t): return t.startAt
        case .blowTurn(let t): return t.startAt
        case .humTurn(let t): return t.startAt
        case .safeTurn(let t): return t.startAt
        case .beatTurn(let t): return t.startAt
        case .sizeTurn(let t): return t.startAt
        case .spotTurn(let t): return t.startAt
        case .oddTurn(let t): return t.startAt
        case .traceTurn(let t): return t.startAt
        case .trafficTurn(let t): return t.startAt
        default: return nil
        }
    }
}

/// Every device — the host included — runs a session. It replays the host's
/// sequenced, encrypted message stream and derives the entire game state
/// from it, so relaunching the app mid-game rebuilds everything by replaying
/// from sequence 0. Input (joining, choosing, answering) goes back out as
/// encrypted player messages at record IDs the host polls.
@MainActor
@Observable
final class GameSession {
    let saved: SavedGame

    private(set) var phase: GamePhase = .lobby(joined: [1])
    private(set) var config: GameConfig?
    private(set) var points: [Int: Int] = [:]
    private(set) var roundsWon: [Int: Int] = [:]
    /// Everyone who had joined by the time the game started. Joins only
    /// happen in the lobby, so the last lobby message is authoritative.
    private(set) var joinedSlots: Set<Int> = [1]
    /// Set when the host announces a rematch after this game ends.
    private(set) var pendingRematch: RematchInvite?
    /// False while the initial replay is draining the stream, so the UI can
    /// skip animating through historical phases.
    private(set) var caughtUp = false
    private(set) var lastError: String?

    private let transport: any GameTransport
    private let crypto: GameCrypto
    private var nextSeq = 0
    private var pollTask: Task<Void, Never>?
    private var submittedAnswerIDs: Set<String> = []

    init(saved: SavedGame, transport: any GameTransport, crypto: GameCrypto) {
        self.saved = saved
        self.transport = transport
        self.crypto = crypto
        self.config = saved.hostConfig
    }

    var mySlot: Int { saved.mySlot }
    var players: [PlayerInfo] { config?.players ?? [] }

    /// My simplification level, nil when off. Drives all the client-side
    /// hints; the host handles the parts that need its secrets.
    var myAssist: AssistLevel? { config?.player(mySlot)?.assist }

    func name(_ slot: Int) -> String {
        config?.name(slot) ?? "Player \(slot)"
    }

    /// The player's dealt color, fixed for the whole game.
    func color(_ slot: Int) -> Color {
        config?.player(slot)?.color ?? PlayerStyle.color(for: slot)
    }

    /// "Ann", "Ann & Bob", "Ann, Bob & Cat".
    func names(_ slots: [Int]) -> String {
        let list = slots.map { name($0) }
        guard list.count > 1 else { return list.first ?? "" }
        return list.dropLast().joined(separator: ", ") + " & " + (list.last ?? "")
    }

    func start() {
        guard pollTask == nil else { return }
        if !saved.isHost {
            Task { await publishJoin() }
        }
        pollTask = Task { await poll() }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Player input

    func submitChoice(round: Int, game: MiniGameType) {
        let id = RecordName.choice(saved.gameID, round: round, slot: mySlot)
        Task {
            await publish(PlayerMessage.choice(round: round, slot: mySlot, game: game), id: id)
        }
    }

    func submitAnswer(bearing: Double?, for turnStart: TurnStart) {
        let id = RecordName.answer(saved.gameID, round: turnStart.round, turn: turnStart.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            let coordinate = await LocationService.shared.currentCoordinate()
            let answer = DirectionAnswer(
                round: turnStart.round,
                turn: turnStart.turn,
                slot: mySlot,
                bearing: bearing,
                coordinate: coordinate,
                submittedAt: Date()
            )
            await publish(PlayerMessage.answer(answer), id: id)
        }
    }

    func hasSubmittedAnswer(for turnStart: TurnStart) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.answer(saved.gameID, round: turnStart.round, turn: turnStart.turn, slot: mySlot)
        )
    }

    // MARK: - Hide & Seek input

    /// My hiding spot per round, so the grid can mark it. Only kept in
    /// memory — after a relaunch the marker is lost but the host still has
    /// the authoritative spot.
    private(set) var myHideCells: [Int: Int] = [:]

    func submitHide(cell: Int, for hideStart: HideStart) {
        guard myHideCells[hideStart.round] == nil else { return }
        myHideCells[hideStart.round] = cell
        let id = RecordName.hide(saved.gameID, round: hideStart.round, slot: mySlot)
        Task {
            await publish(PlayerMessage.hide(round: hideStart.round, slot: mySlot, cell: cell), id: id)
        }
    }

    func hasSubmittedHide(for hideStart: HideStart) -> Bool {
        myHideCells[hideStart.round] != nil
    }

    func submitSeek(cell: Int, for turnStart: SeekTurnStart) {
        let id = RecordName.seek(saved.gameID, round: turnStart.round, turn: turnStart.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.seek(round: turnStart.round, turn: turnStart.turn, slot: mySlot, cell: cell), id: id)
        }
    }

    func hasSubmittedSeek(for turnStart: SeekTurnStart) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.seek(saved.gameID, round: turnStart.round, turn: turnStart.turn, slot: mySlot)
        )
    }

    // MARK: - Higher or Lower input

    func submitGuess(_ guess: HigherLowerGuess, for turn: CardTurn) {
        let id = RecordName.guess(saved.gameID, round: turn.round, match: turn.match, step: turn.step, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.guess(round: turn.round, match: turn.match, step: turn.step, slot: mySlot, guess: guess),
                id: id
            )
        }
    }

    func hasSubmittedGuess(for turn: CardTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.guess(saved.gameID, round: turn.round, match: turn.match, step: turn.step, slot: mySlot)
        )
    }

    // MARK: - Repeat After Me input

    func submitSequence(taps: [Int], for turn: SequenceTurn) {
        let id = RecordName.sequenceAnswer(saved.gameID, round: turn.round, match: turn.match, step: turn.step, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.sequenceAnswer(round: turn.round, match: turn.match, step: turn.step, slot: mySlot, taps: taps),
                id: id
            )
        }
    }

    func hasSubmittedSequence(for turn: SequenceTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.sequenceAnswer(saved.gameID, round: turn.round, match: turn.match, step: turn.step, slot: mySlot)
        )
    }

    // MARK: - Lightning input

    func submitReaction(elapsedMs: Int?, falseStart: Bool, for turn: FlashTurn) {
        let id = RecordName.reaction(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.reaction(round: turn.round, turn: turn.turn, slot: mySlot, elapsedMs: elapsedMs, falseStart: falseStart),
                id: id
            )
        }
    }

    func hasSubmittedReaction(for turn: FlashTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.reaction(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Put Your Finger On It input

    func submitFinger(coordinate: Coordinate, for turn: FingerTurn) {
        let id = RecordName.fingerGuess(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.fingerGuess(round: turn.round, turn: turn.turn, slot: mySlot, coordinate: coordinate),
                id: id
            )
        }
    }

    func hasSubmittedFinger(for turn: FingerTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.fingerGuess(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Ten Seconds input

    func submitClockTap(elapsedMs: Int, for turn: ClockTurn) {
        let id = RecordName.clockTap(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.clockTap(round: turn.round, turn: turn.turn, slot: mySlot, elapsedMs: elapsedMs),
                id: id
            )
        }
    }

    func hasSubmittedClockTap(for turn: ClockTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.clockTap(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Push Your Luck input

    func submitDice(push: Bool, for step: DiceStep) {
        let id = RecordName.dice(saved.gameID, round: step.round, run: step.run, step: step.step, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.dice(round: step.round, run: step.run, step: step.step, slot: mySlot, push: push),
                id: id
            )
        }
    }

    func hasSubmittedDice(for step: DiceStep) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.dice(saved.gameID, round: step.round, run: step.run, step: step.step, slot: mySlot)
        )
    }

    // MARK: - Gold Rush input

    func submitGold(cell: Int, for turn: GoldTurn) {
        let id = RecordName.goldPick(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.goldPick(round: turn.round, turn: turn.turn, slot: mySlot, cell: cell),
                id: id
            )
        }
    }

    func hasSubmittedGold(for turn: GoldTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.goldPick(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Eyeball It input

    func submitEyeball(guess: Int, for turn: EyeballTurn) {
        let id = RecordName.eyeball(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.eyeball(round: turn.round, turn: turn.turn, slot: mySlot, guess: guess),
                id: id
            )
        }
    }

    func hasSubmittedEyeball(for turn: EyeballTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.eyeball(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Perfect Circle input

    func submitCircle(path: [Double], for turn: CircleTurn) {
        let id = RecordName.circleDraw(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.circleDraw(round: turn.round, turn: turn.turn, slot: mySlot, path: path),
                id: id
            )
        }
    }

    func hasSubmittedCircle(for turn: CircleTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.circleDraw(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Sort Circuit input

    func submitSort(elapsedMs: Int, mistakes: Int, for turn: SortTurn) {
        let id = RecordName.sortTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.sortTime(round: turn.round, turn: turn.turn, slot: mySlot, elapsedMs: elapsedMs, mistakes: mistakes),
                id: id
            )
        }
    }

    func hasSubmittedSort(for turn: SortTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.sortTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Steady Hand input

    func submitSteady(survivedMs: Int, for turn: SteadyTurn) {
        let id = RecordName.steadyTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.steadyTime(round: turn.round, turn: turn.turn, slot: mySlot, survivedMs: survivedMs),
                id: id
            )
        }
    }

    func hasSubmittedSteady(for turn: SteadyTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.steadyTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Showdown input

    func submitShowdown(throwing: RPSThrow, for turn: ShowdownTurn) {
        let id = RecordName.showdownThrow(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.showdownThrow(round: turn.round, turn: turn.turn, slot: mySlot, throwing: throwing),
                id: id
            )
        }
    }

    func hasSubmittedShowdown(for turn: ShowdownTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.showdownThrow(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Tap Frenzy input

    func submitFrenzy(taps: Int, for turn: FrenzyTurn) {
        let id = RecordName.frenzyTaps(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.frenzyTaps(round: turn.round, turn: turn.turn, slot: mySlot, taps: taps),
                id: id
            )
        }
    }

    func hasSubmittedFrenzy(for turn: FrenzyTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.frenzyTaps(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Globetrotter input

    func submitGlobe(coordinate: Coordinate, for turn: GlobeTurn) {
        let id = RecordName.globeGuess(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.globeGuess(round: turn.round, turn: turn.turn, slot: mySlot, coordinate: coordinate),
                id: id
            )
        }
    }

    func hasSubmittedGlobe(for turn: GlobeTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.globeGuess(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Colour Clash input

    func submitClash(elapsedMs: Int, mistakes: Int, for turn: ClashTurn) {
        let id = RecordName.clashTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.clashTime(round: turn.round, turn: turn.turn, slot: mySlot, elapsedMs: elapsedMs, mistakes: mistakes),
                id: id
            )
        }
    }

    func hasSubmittedClash(for turn: ClashTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.clashTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Spirit Level input

    func submitLevel(heldMs: Int, for turn: LevelTurn) {
        let id = RecordName.levelHeld(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.levelHeld(round: turn.round, turn: turn.turn, slot: mySlot, heldMs: heldMs),
                id: id
            )
        }
    }

    func hasSubmittedLevel(for turn: LevelTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.levelHeld(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Pour It input

    func submitPour(fillPercent: Int, overflowed: Bool, for turn: PourTurn) {
        let id = RecordName.pourFill(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.pourFill(round: turn.round, turn: turn.turn, slot: mySlot, fillPercent: fillPercent, overflowed: overflowed),
                id: id
            )
        }
    }

    func hasSubmittedPour(for turn: PourTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.pourFill(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Marble Maze input

    func submitMaze(elapsedMs: Int, for turn: MazeTurn) {
        let id = RecordName.mazeTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(
                PlayerMessage.mazeTime(round: turn.round, turn: turn.turn, slot: mySlot, elapsedMs: elapsedMs),
                id: id
            )
        }
    }

    func hasSubmittedMaze(for turn: MazeTurn) -> Bool {
        submittedAnswerIDs.contains(
            RecordName.mazeTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        )
    }

    // MARK: - Loudest input

    func submitLoud(level: Int, for turn: LoudTurn) {
        let id = RecordName.loudLevel(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.loudLevel(round: turn.round, turn: turn.turn, slot: mySlot, level: level), id: id)
        }
    }

    func hasSubmittedLoud(for turn: LoudTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.loudLevel(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Blow It Out input

    func submitBlow(candles: Int, for turn: BlowTurn) {
        let id = RecordName.blowCandles(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.blowCandles(round: turn.round, turn: turn.turn, slot: mySlot, candles: candles), id: id)
        }
    }

    func hasSubmittedBlow(for turn: BlowTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.blowCandles(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Hum It input

    func submitHum(errorCents: Int, for turn: HumTurn) {
        let id = RecordName.humPitch(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.humPitch(round: turn.round, turn: turn.turn, slot: mySlot, errorCents: errorCents), id: id)
        }
    }

    func hasSubmittedHum(for turn: HumTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.humPitch(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Crack the Safe input

    func submitSafe(elapsedMs: Int, for turn: SafeTurn) {
        let id = RecordName.safeTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.safeTime(round: turn.round, turn: turn.turn, slot: mySlot, elapsedMs: elapsedMs), id: id)
        }
    }

    func hasSubmittedSafe(for turn: SafeTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.safeTime(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Feel the Beat input

    func submitBeat(errorMs: Int, for turn: BeatTurn) {
        let id = RecordName.beatError(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.beatError(round: turn.round, turn: turn.turn, slot: mySlot, errorMs: errorMs), id: id)
        }
    }

    func hasSubmittedBeat(for turn: BeatTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.beatError(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Size It Up input

    func submitSize(sizePerMille: Int, for turn: SizeTurn) {
        let id = RecordName.sizeDraw(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.sizeDraw(round: turn.round, turn: turn.turn, slot: mySlot, sizePerMille: sizePerMille), id: id)
        }
    }

    func hasSubmittedSize(for turn: SizeTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.sizeDraw(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Spot Recall input

    func submitSpot(errorPerMille: Int, for turn: SpotTurn) {
        let id = RecordName.spotGuess(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.spotGuess(round: turn.round, turn: turn.turn, slot: mySlot, errorPerMille: errorPerMille), id: id)
        }
    }

    func hasSubmittedSpot(for turn: SpotTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.spotGuess(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Odd One Out input

    func submitOdd(timeMs: Int, for turn: OddTurn) {
        let id = RecordName.oddTap(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.oddTap(round: turn.round, turn: turn.turn, slot: mySlot, timeMs: timeMs), id: id)
        }
    }

    func hasSubmittedOdd(for turn: OddTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.oddTap(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Trace It input

    func submitTrace(errorPerMille: Int, for turn: TraceTurn) {
        let id = RecordName.traceDraw(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.traceDraw(round: turn.round, turn: turn.turn, slot: mySlot, errorPerMille: errorPerMille), id: id)
        }
    }

    func hasSubmittedTrace(for turn: TraceTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.traceDraw(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    // MARK: - Traffic Light input

    func submitTraffic(reactionMs: Int?, falseStart: Bool, for turn: TrafficTurn) {
        let id = RecordName.trafficTap(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot)
        guard !submittedAnswerIDs.contains(id) else { return }
        submittedAnswerIDs.insert(id)
        Task {
            await publish(PlayerMessage.trafficTap(round: turn.round, turn: turn.turn, slot: mySlot, reactionMs: reactionMs, falseStart: falseStart), id: id)
        }
    }

    func hasSubmittedTraffic(for turn: TrafficTurn) -> Bool {
        submittedAnswerIDs.contains(RecordName.trafficTap(saved.gameID, round: turn.round, turn: turn.turn, slot: mySlot))
    }

    private func publishJoin() async {
        let coordinate = await LocationService.shared.currentCoordinate()
        let name = UserDefaults.standard.string(forKey: "myName") ?? ""
        let message = PlayerMessage.join(
            slot: saved.mySlot, name: name, coordinate: coordinate,
            protocolVersion: AppProtocol.current
        )
        await publish(message, id: RecordName.join(saved.gameID, slot: saved.mySlot))
    }

    private func publish(_ message: PlayerMessage, id: String) async {
        do {
            let body = try crypto.seal(message)
            try await transport.put(id: id, body: body)
            lastError = nil
        } catch {
            lastError = "Couldn't send: \(error.localizedDescription)"
        }
    }

    // MARK: - Host stream replay

    private func poll() async {
        while !Task.isCancelled {
            await fetchNextMessages()
            caughtUp = true
            try? await Task.sleep(for: .seconds(0.75))
        }
    }

    private func fetchNextMessages() async {
        while !Task.isCancelled {
            let ids = (nextSeq..<(nextSeq + 5)).map { RecordName.host(saved.gameID, seq: $0) }
            guard let found = try? await transport.get(ids: ids), !found.isEmpty else { return }
            var advanced = false
            while let body = found[RecordName.host(saved.gameID, seq: nextSeq)] {
                guard let message = try? crypto.open(HostMessage.self, from: body) else {
                    // Either the link/key is wrong, or the host is on a newer
                    // wire format we can't read yet.
                    lastError = "Couldn't read a game message — check the link is right, and that your app is up to date."
                    return
                }
                apply(message)
                nextSeq += 1
                advanced = true
            }
            // Only keep looping if the whole batch was present (fast replay).
            if !advanced || found.count < ids.count { return }
        }
    }

    /// Screenshot-tour support: force state directly, bypassing the
    /// message stream. Only ever driven by the simulator-only demo tour.
    func applyDemoState(
        config: GameConfig,
        points: [Int: Int],
        roundsWon: [Int: Int],
        joined: Set<Int>,
        phase: GamePhase
    ) {
        self.config = config
        self.points = points
        self.roundsWon = roundsWon
        self.joinedSlots = joined
        self.phase = phase
    }

    private func apply(_ message: HostMessage) {
        switch message {
        case .gameCreated(let config):
            self.config = config
            // A host on a newer wire format than we understand — warn rather
            // than fail cryptically later.
            if config.wireVersion > AppProtocol.current {
                lastError = "This game needs a newer version of the app — check the App Store for an update."
            }
        case .lobby(let joined):
            joinedSlots = Set(joined)
            if case .lobby = phase {
                phase = .lobby(joined: Set(joined))
            }
        case .wheel(let round, let chooser, let spinSeconds, let maxGameVersion):
            points = [:]
            phase = .wheel(round: round, chooser: chooser, spinSeconds: spinSeconds, maxGameVersion: maxGameVersion)
        case .roundStart(let round, let game):
            phase = .roundIntro(round: round, game: game)
        case .turnStart(let turnStart):
            phase = .turn(turnStart)
        case .turnReveal(let reveal):
            points = reveal.points
            phase = .reveal(reveal)
        case .hideStart(let hideStart):
            phase = .hiding(hideStart)
        case .seekTurn(let turnStart):
            phase = .seekTurn(turnStart)
        case .seekReveal(let reveal):
            phase = .seekReveal(reveal)
        case .cardTurn(let turn):
            points = turn.points
            phase = .cardGuess(turn)
        case .cardReveal(let reveal):
            points = reveal.points
            phase = .cardReveal(reveal)
        case .sequenceTurn(let turn):
            points = turn.points
            phase = .sequenceTurn(turn)
        case .sequenceReveal(let reveal):
            points = reveal.points
            phase = .sequenceReveal(reveal)
        case .flashTurn(let turn):
            points = turn.points
            phase = .flashTurn(turn)
        case .flashReveal(let reveal):
            points = reveal.points
            phase = .flashReveal(reveal)
        case .fingerTurn(let turn):
            points = turn.points
            phase = .fingerTurn(turn)
        case .fingerReveal(let reveal):
            points = reveal.points
            phase = .fingerReveal(reveal)
        case .clockTurn(let turn):
            points = turn.points
            phase = .clockTurn(turn)
        case .clockReveal(let reveal):
            points = reveal.points
            phase = .clockReveal(reveal)
        case .diceStep(let step):
            points = step.banks
            phase = .diceStep(step)
        case .diceReveal(let reveal):
            points = reveal.banks
            phase = .diceReveal(reveal)
        case .goldTurn(let turn):
            points = turn.totals
            phase = .goldTurn(turn)
        case .goldReveal(let reveal):
            points = reveal.totals
            phase = .goldReveal(reveal)
        case .eyeballTurn(let turn):
            points = turn.points
            phase = .eyeballTurn(turn)
        case .eyeballReveal(let reveal):
            points = reveal.points
            phase = .eyeballReveal(reveal)
        case .circleTurn(let turn):
            points = turn.points
            phase = .circleTurn(turn)
        case .circleReveal(let reveal):
            points = reveal.points
            phase = .circleReveal(reveal)
        case .sortTurn(let turn):
            points = turn.points
            phase = .sortTurn(turn)
        case .sortReveal(let reveal):
            points = reveal.points
            phase = .sortReveal(reveal)
        case .steadyTurn(let turn):
            points = turn.points
            phase = .steadyTurn(turn)
        case .steadyReveal(let reveal):
            points = reveal.points
            phase = .steadyReveal(reveal)
        case .showdownTurn(let turn):
            points = turn.totals
            phase = .showdownTurn(turn)
        case .showdownReveal(let reveal):
            points = reveal.totals
            phase = .showdownReveal(reveal)
        case .frenzyTurn(let turn):
            points = turn.points
            phase = .frenzyTurn(turn)
        case .frenzyReveal(let reveal):
            points = reveal.points
            phase = .frenzyReveal(reveal)
        case .globeTurn(let turn):
            points = turn.points
            phase = .globeTurn(turn)
        case .globeReveal(let reveal):
            points = reveal.points
            phase = .globeReveal(reveal)
        case .clashTurn(let turn):
            points = turn.points
            phase = .clashTurn(turn)
        case .clashReveal(let reveal):
            points = reveal.points
            phase = .clashReveal(reveal)
        case .levelTurn(let turn):
            points = turn.points
            phase = .levelTurn(turn)
        case .levelReveal(let reveal):
            points = reveal.points
            phase = .levelReveal(reveal)
        case .pourTurn(let turn):
            points = turn.points
            phase = .pourTurn(turn)
        case .pourReveal(let reveal):
            points = reveal.points
            phase = .pourReveal(reveal)
        case .mazeTurn(let turn):
            points = turn.points
            phase = .mazeTurn(turn)
        case .mazeReveal(let reveal):
            points = reveal.points
            phase = .mazeReveal(reveal)
        case .loudTurn(let turn):
            points = turn.points
            phase = .loudTurn(turn)
        case .loudReveal(let reveal):
            points = reveal.points
            phase = .loudReveal(reveal)
        case .blowTurn(let turn):
            points = turn.points
            phase = .blowTurn(turn)
        case .blowReveal(let reveal):
            points = reveal.points
            phase = .blowReveal(reveal)
        case .humTurn(let turn):
            points = turn.points
            phase = .humTurn(turn)
        case .humReveal(let reveal):
            points = reveal.points
            phase = .humReveal(reveal)
        case .safeTurn(let turn):
            points = turn.points
            phase = .safeTurn(turn)
        case .safeReveal(let reveal):
            points = reveal.points
            phase = .safeReveal(reveal)
        case .beatTurn(let turn):
            points = turn.points
            phase = .beatTurn(turn)
        case .beatReveal(let reveal):
            points = reveal.points
            phase = .beatReveal(reveal)
        case .sizeTurn(let turn):
            points = turn.points
            phase = .sizeTurn(turn)
        case .sizeReveal(let reveal):
            points = reveal.points
            phase = .sizeReveal(reveal)
        case .spotTurn(let turn):
            points = turn.points
            phase = .spotTurn(turn)
        case .spotReveal(let reveal):
            points = reveal.points
            phase = .spotReveal(reveal)
        case .oddTurn(let turn):
            points = turn.points
            phase = .oddTurn(turn)
        case .oddReveal(let reveal):
            points = reveal.points
            phase = .oddReveal(reveal)
        case .traceTurn(let turn):
            points = turn.points
            phase = .traceTurn(turn)
        case .traceReveal(let reveal):
            points = reveal.points
            phase = .traceReveal(reveal)
        case .trafficTurn(let turn):
            points = turn.points
            phase = .trafficTurn(turn)
        case .trafficReveal(let reveal):
            points = reveal.points
            phase = .trafficReveal(reveal)
        case .tieBreakSpin(let candidates, let winner, let spinSeconds):
            phase = .tieBreak(candidates: candidates, winner: winner, spinSeconds: spinSeconds)
        case .roundEnd(let round, let winners, let rounds):
            roundsWon = rounds
            phase = .roundEnd(round: round, winners: winners)
        case .gameEnd(let winner, let rounds):
            roundsWon = rounds
            phase = .gameEnd(winner: winner)
        case .rematch(let invite):
            // The host initiated it; only joiners need the prompt.
            if !saved.isHost {
                pendingRematch = invite
            }
        }
    }
}
