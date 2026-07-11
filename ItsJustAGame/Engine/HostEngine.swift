import Foundation
import Observation

/// Runs only on the device that created the game. All randomness (the wheel
/// result, the target locations) and all scoring happen here; other devices
/// only ever see the resulting encrypted host messages. The host device also
/// runs a normal GameSession to play its own turns — the engine treats
/// player 1 exactly like everyone else.
@MainActor
@Observable
final class HostEngine {
    let config: GameConfig

    private(set) var joined: Set<Int> = [1]
    private(set) var gameRunning = false
    private(set) var resumeBlocked = false
    private(set) var lastError: String?

    private let transport: any GameTransport
    private let crypto: GameCrypto
    private var seq = 0
    private var lobbyTask: Task<Void, Never>?
    private var gameTask: Task<Void, Never>?
    private var playerCoordinates: [Int: Coordinate] = [:]
    private var lastChooser: Int?

    init(config: GameConfig, transport: any GameTransport, crypto: GameCrypto) {
        self.config = config
        self.transport = transport
        self.crypto = crypto
    }

    func start() {
        guard lobbyTask == nil, gameTask == nil else { return }
        lobbyTask = Task { await runLobby() }
    }

    func stop() {
        lobbyTask?.cancel()
        gameTask?.cancel()
        lobbyTask = nil
        gameTask = nil
    }

    var canBeginGame: Bool {
        !gameRunning && !resumeBlocked && joined.count >= MiniGameType.smallestMinimum
    }

    func beginGame() {
        guard canBeginGame else { return }
        gameRunning = true
        lobbyTask?.cancel()
        lobbyTask = nil
        gameTask = Task { await runGame() }
    }

    // MARK: - Lobby

    private func runLobby() async {
        await recoverPublishedMessages()
        if resumeBlocked { return }
        if seq == 0 {
            await send(.gameCreated(config: config))
            await send(.lobby(joined: joined.sorted()))
        }
        if let coordinate = await LocationService.shared.currentCoordinate() {
            playerCoordinates[1] = coordinate
        }
        while !Task.isCancelled && !gameRunning {
            await pollJoins()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// After a relaunch, walk our own message stream forward to find the
    /// next free sequence number. If the game had already started we can't
    /// safely resume the host loop yet (v1 limitation) — flag it for the UI.
    private func recoverPublishedMessages() async {
        while true {
            let ids = (seq..<(seq + 10)).map { RecordName.host(config.gameID, seq: $0) }
            guard let found = try? await transport.get(ids: ids), !found.isEmpty else { return }
            var advanced = false
            while let body = found[RecordName.host(config.gameID, seq: seq)] {
                if let message = try? crypto.open(HostMessage.self, from: body) {
                    if case .lobby(let slots) = message { joined = Set(slots) }
                    if case .wheel = message { resumeBlocked = true }
                }
                seq += 1
                advanced = true
            }
            if !advanced || found.count < ids.count { return }
        }
    }

    private func pollJoins() async {
        let waiting = config.players.map(\.slot).filter { $0 != 1 && !joined.contains($0) }
        guard !waiting.isEmpty else { return }
        let ids = waiting.map { RecordName.join(config.gameID, slot: $0) }
        guard let found = try? await transport.get(ids: ids), !found.isEmpty else { return }
        var changed = false
        for body in found.values {
            guard let message = try? crypto.open(PlayerMessage.self, from: body),
                  case .join(let slot, _, let coordinate) = message else { continue }
            if !joined.contains(slot) {
                joined.insert(slot)
                changed = true
            }
            if let coordinate {
                playerCoordinates[slot] = coordinate
            }
        }
        if changed {
            await send(.lobby(joined: joined.sorted()))
        }
    }

    // MARK: - Game loop

    private func runGame() async {
        var roundsWon: [Int: Int] = [:]
        var round = 1
        while !Task.isCancelled {
            let chooser = pickChooser()
            lastChooser = chooser
            await send(.wheel(round: round, chooser: chooser))
            let game = await waitForChoice(round: round, chooser: chooser)
            await send(.roundStart(round: round, game: game))
            try? await Task.sleep(for: .seconds(3))
            let winner = await runDirectionRound(round: round)
            roundsWon[winner, default: 0] += 1
            if roundsWon[winner, default: 0] >= config.roundsToWin {
                await send(.gameEnd(winner: winner, roundsWon: roundsWon))
                gameRunning = false
                return
            }
            await send(.roundEnd(round: round, winner: winner, roundsWon: roundsWon))
            try? await Task.sleep(for: .seconds(GameTiming.betweenRoundsSeconds))
            round += 1
        }
    }

    private func pickChooser() -> Int {
        let slots = joined.sorted()
        let candidates = slots.count > 1 ? slots.filter { $0 != lastChooser } : slots
        return candidates.randomElement() ?? 1
    }

    private func waitForChoice(round: Int, chooser: Int) async -> MiniGameType {
        // Give the wheel animation time to play everywhere before looking.
        try? await Task.sleep(for: .seconds(GameTiming.wheelSpinSeconds))
        let id = RecordName.choice(config.gameID, round: round, slot: chooser)
        let deadline = Date().addingTimeInterval(120)
        while !Task.isCancelled && Date() < deadline {
            if let found = try? await transport.get(ids: [id]),
               let body = found[id],
               let message = try? crypto.open(PlayerMessage.self, from: body),
               case .choice(_, _, let game) = message {
                // The host is authoritative: a game without enough players
                // can't be chosen, whatever the chooser's device claimed.
                if joined.count >= game.minPlayers {
                    return game
                }
                break
            }
            try? await Task.sleep(for: .seconds(1.5))
        }
        return MiniGameType.available(for: joined.count).randomElement() ?? .senseOfDirection
    }

    private func runDirectionRound(round: Int) async -> Int {
        var points: [Int: Int] = [:]
        var usedNames: Set<String> = []
        var turn = 1
        while !Task.isCancelled {
            let target = await LocationPicker.pickTarget(
                near: Array(playerCoordinates.values),
                excluding: usedNames
            )
            usedNames.insert(target.name)
            let turnStart = TurnStart(
                round: round,
                turn: turn,
                target: target,
                startAt: Date().addingTimeInterval(3),
                introSeconds: GameTiming.introSeconds,
                aimSeconds: GameTiming.aimSeconds
            )
            await send(.turnStart(turnStart))
            let answers = await collectAnswers(for: turnStart)
            let reveal = score(turnStart: turnStart, answers: answers, points: &points)
            await send(.turnReveal(reveal))
            if let roundWinner = reveal.roundWinner {
                return roundWinner
            }
            try? await Task.sleep(for: .seconds(GameTiming.revealSeconds))
            turn += 1
        }
        return 1
    }

    private func collectAnswers(for turnStart: TurnStart) async -> [Int: DirectionAnswer] {
        let slots = joined.sorted()
        let deadline = turnStart.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var answers: [Int: DirectionAnswer] = [:]
        while !Task.isCancelled {
            let missing = slots.filter { answers[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.answer(config.gameID, round: turnStart.round, turn: turnStart.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .answer(let answer) = message else { continue }
                    answers[answer.slot] = answer
                    if let coordinate = answer.coordinate {
                        playerCoordinates[answer.slot] = coordinate
                    }
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(1.5))
        }
        return answers
    }

    private func score(turnStart: TurnStart, answers: [Int: DirectionAnswer], points: inout [Int: Int]) -> TurnReveal {
        var outcomes: [PlayerOutcome] = []
        for slot in joined.sorted() {
            let answer = answers[slot]
            let coordinate = answer?.coordinate
            let correct = coordinate.map { DirectionMath.initialBearing(from: $0, to: turnStart.target.coordinate) }
            var error: Double?
            if let bearing = answer?.bearing, let correct {
                error = DirectionMath.angularError(bearing, correct)
            }
            outcomes.append(PlayerOutcome(
                slot: slot,
                bearing: answer?.bearing,
                correctBearing: correct,
                errorDegrees: error,
                coordinate: coordinate
            ))
        }

        let scored = outcomes.filter { $0.errorDegrees != nil }
        let winner = scored.min { a, b in
            if a.errorDegrees! != b.errorDegrees! {
                return a.errorDegrees! < b.errorDegrees!
            }
            let aTime = answers[a.slot]?.submittedAt ?? .distantFuture
            let bTime = answers[b.slot]?.submittedAt ?? .distantFuture
            return aTime < bTime
        }?.slot

        if let winner {
            points[winner, default: 0] += 1
        }

        var roundWinner: Int?
        if let winner, points[winner, default: 0] >= GameTiming.pointsToWinRound {
            roundWinner = winner
        } else if turnStart.turn >= GameTiming.maxTurnsPerRound {
            // Safety valve so a round can't run forever if nobody scores.
            roundWinner = points.max { $0.value < $1.value }?.key
                ?? winner
                ?? joined.sorted().randomElement()
                ?? 1
        }

        return TurnReveal(
            round: turnStart.round,
            turn: turnStart.turn,
            target: turnStart.target,
            outcomes: outcomes,
            winner: winner,
            points: points,
            roundWinner: roundWinner,
            nextTurnAt: roundWinner == nil ? Date().addingTimeInterval(GameTiming.revealSeconds + 3) : nil
        )
    }

    private func send(_ message: HostMessage) async {
        for attempt in 0..<3 {
            do {
                let body = try crypto.seal(message)
                try await transport.put(id: RecordName.host(config.gameID, seq: seq), body: body)
                seq += 1
                lastError = nil
                return
            } catch {
                lastError = "Couldn't publish: \(error.localizedDescription)"
                if attempt < 2 {
                    try? await Task.sleep(for: .seconds(2))
                }
            }
        }
    }
}
