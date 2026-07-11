import Foundation
import Observation

enum GamePhase: Hashable {
    case lobby(joined: Set<Int>)
    case wheel(round: Int, chooser: Int)
    case roundIntro(round: Int, game: MiniGameType)
    case turn(TurnStart)
    case reveal(TurnReveal)
    case roundEnd(round: Int, winner: Int)
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
            try? await Task.sleep(for: .seconds(1.5))
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
        case .wheel(let round, let chooser):
            points = [:]
            phase = .wheel(round: round, chooser: chooser)
        case .roundStart(let round, let game):
            phase = .roundIntro(round: round, game: game)
        case .turnStart(let turnStart):
            phase = .turn(turnStart)
        case .turnReveal(let reveal):
            points = reveal.points
            phase = .reveal(reveal)
        case .roundEnd(let round, let winner, let rounds):
            roundsWon = rounds
            phase = .roundEnd(round: round, winner: winner)
        case .gameEnd(let winner, let rounds):
            roundsWon = rounds
            phase = .gameEnd(winner: winner)
        }
    }
}
