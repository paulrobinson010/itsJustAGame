import Foundation
import Observation
import SwiftUI

enum GamePhase: Hashable {
    case lobby(joined: Set<Int>)
    case wheel(round: Int, chooser: Int, spinSeconds: Double)
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
    case roundEnd(round: Int, winners: [Int])
    case tieBreak(candidates: [Int], winner: Int, spinSeconds: Double)
    case gameEnd(winner: Int)
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

    private func publishJoin() async {
        let coordinate = await LocationService.shared.currentCoordinate()
        let name = UserDefaults.standard.string(forKey: "myName") ?? ""
        let message = PlayerMessage.join(slot: saved.mySlot, name: name, coordinate: coordinate)
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
                    lastError = "Couldn't decrypt a game message — is the link right?"
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

    private func apply(_ message: HostMessage) {
        switch message {
        case .gameCreated(let config):
            self.config = config
        case .lobby(let joined):
            joinedSlots = Set(joined)
            if case .lobby = phase {
                phase = .lobby(joined: Set(joined))
            }
        case .wheel(let round, let chooser, let spinSeconds):
            points = [:]
            phase = .wheel(round: round, chooser: chooser, spinSeconds: spinSeconds)
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
