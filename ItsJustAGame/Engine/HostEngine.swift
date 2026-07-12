import Foundation
import Observation
import SwiftUI

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
    /// Rematch games begin on their own once everyone has rejoined.
    private let autoStart: Bool
    private var seq = 0
    private var lobbyTask: Task<Void, Never>?
    private var gameTask: Task<Void, Never>?
    private var playerCoordinates: [Int: Coordinate] = [:]
    private var lastChooser: Int?

    init(config: GameConfig, transport: any GameTransport, crypto: GameCrypto, autoStart: Bool = false) {
        self.config = config
        self.transport = transport
        self.crypto = crypto
        self.autoStart = autoStart
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

    /// Screenshot-tour support (simulator-only demo).
    func applyDemoJoined(_ slots: Set<Int>) {
        joined = slots
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
        let lobbyOpenedAt = Date()
        while !Task.isCancelled && !gameRunning {
            await pollJoins()
            if autoStart {
                let everyone = Set(config.players.map(\.slot))
                let waitedLongEnough = Date().timeIntervalSince(lobbyOpenedAt) > 25
                if joined == everyone || (waitedLongEnough && joined.count >= MiniGameType.smallestMinimum) {
                    beginGame()
                    break
                }
            }
            try? await Task.sleep(for: .seconds(1))
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
                    if case .rematch(let invite) = message {
                        // A rematch already exists — reuse it, never mint a second.
                        existingRematch = invite
                        rematchAnnounced = true
                    }
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
            let spinSeconds = Double.random(in: 3...10)
            await send(.wheel(round: round, chooser: chooser, spinSeconds: spinSeconds))
            let game = await waitForChoice(round: round, chooser: chooser, spinSeconds: spinSeconds)
            await send(.roundStart(round: round, game: game))
            try? await Task.sleep(for: .seconds(3))
            let winners: [Int]
            switch game {
            case .senseOfDirection:
                winners = [await runDirectionRound(round: round)]
            case .hideAndSeek:
                winners = await runHideAndSeekRound(round: round)
            case .higherOrLower:
                winners = await runHigherLowerRound(round: round)
            case .repeatAfterMe:
                winners = await runRepeatAfterMeRound(round: round)
            case .lightning:
                winners = await runLightningRound(round: round)
            case .putYourFingerOnIt:
                winners = await runFingerRound(round: round)
            case .tenSeconds:
                winners = await runClockRound(round: round)
            case .pushYourLuck:
                winners = await runDiceRound(round: round)
            case .goldRush:
                winners = await runGoldRound(round: round)
            case .eyeballIt:
                winners = await runEyeballRound(round: round)
            case .perfectCircle:
                winners = await runCircleRound(round: round)
            case .sortCircuit:
                winners = await runSortRound(round: round)
            case .steadyHand:
                winners = await runSteadyRound(round: round)
            case .showdown:
                winners = await runShowdownRound(round: round)
            case .tapFrenzy:
                winners = await runFrenzyRound(round: round)
            }
            for winner in winners {
                roundsWon[winner, default: 0] += 1
            }
            let champions = joined.sorted().filter { roundsWon[$0, default: 0] >= config.roundsToWin }
            if champions.count == 1 {
                await send(.gameEnd(winner: champions[0], roundsWon: roundsWon))
                gameRunning = false
                return
            }
            if champions.count > 1 {
                // Several players hit the target together — the wheel picks
                // the overall winner, totally at random.
                let overall = champions.randomElement() ?? champions[0]
                let spinSeconds = Double.random(in: 3...8)
                await send(.tieBreakSpin(candidates: champions, winner: overall, spinSeconds: spinSeconds))
                try? await Task.sleep(for: .seconds(spinSeconds + 3))
                await send(.gameEnd(winner: overall, roundsWon: roundsWon))
                gameRunning = false
                return
            }
            await send(.roundEnd(round: round, winners: winners, roundsWon: roundsWon))
            try? await Task.sleep(for: .seconds(GameTiming.betweenRoundsSeconds))
            round += 1
        }
    }

    /// Announce a fresh game for the same crew over this game's stream.
    /// Returns the new game's SavedGame for this (host) device, or nil if a
    /// rematch was already announced or the game is still running.
    private(set) var rematchAnnounced = false
    /// Found during stream recovery when this game already has a rematch.
    private(set) var existingRematch: RematchInvite?

    func announceRematch() async -> SavedGame? {
        guard !gameRunning, !rematchAnnounced else { return nil }
        rematchAnnounced = true
        let crypto = GameCrypto()
        let colorIndices = Array(0..<PlayerStyle.palette.count).shuffled()
        let players = config.players.enumerated().map { index, player in
            PlayerInfo(
                slot: player.slot,
                name: player.name,
                colorIndex: colorIndices[index % colorIndices.count],
                assist: player.assist
            )
        }
        let newConfig = GameConfig(
            gameID: UUID().uuidString.lowercased(),
            roundsToWin: config.roundsToWin,
            players: players,
            createdAt: Date()
        )
        let invite = RematchInvite(
            newGameID: newConfig.gameID,
            newKeyBase64URL: crypto.base64URL,
            config: newConfig
        )
        await send(.rematch(invite))
        return SavedGame(
            gameID: newConfig.gameID,
            keyBase64URL: crypto.base64URL,
            mySlot: 1,
            isHost: true,
            hostConfig: newConfig,
            title: "\(newConfig.name(1))'s game · \(players.count) players",
            createdAt: Date(),
            autoStart: true
        )
    }

    private func assistLevel(_ slot: Int) -> AssistLevel? {
        config.player(slot)?.assist
    }

    private func pickChooser() -> Int {
        let slots = joined.sorted()
        let candidates = slots.count > 1 ? slots.filter { $0 != lastChooser } : slots
        return candidates.randomElement() ?? 1
    }

    private func waitForChoice(round: Int, chooser: Int, spinSeconds: Double) async -> MiniGameType {
        // Give the wheel animation time to play everywhere before looking.
        try? await Task.sleep(for: .seconds(spinSeconds + 0.5))
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
            try? await Task.sleep(for: .seconds(0.75))
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
            try? await Task.sleep(for: .seconds(0.75))
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

    // MARK: - Hide & Seek

    /// One full match: everyone hides on the grid, then players search in a
    /// shuffled run order until only one player is left hidden — they win
    /// the round. Found players keep taking their seek turns.
    private func runHideAndSeekRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        let gridSize = 5
        let hideStart = HideStart(
            round: round,
            gridSize: gridSize,
            startAt: Date().addingTimeInterval(2),
            hideSeconds: GameTiming.hideSeconds
        )
        await send(.hideStart(hideStart))
        let spots = await collectHideSpots(for: hideStart, players: players)
        let order = players.shuffled()
        var searched: [Int] = []
        var found: [Int: Int] = [:]
        var turn = 1

        while !Task.isCancelled {
            let seeker = order[(turn - 1) % order.count]
            let turnStart = SeekTurnStart(
                round: round,
                turn: turn,
                seeker: seeker,
                order: order,
                gridSize: gridSize,
                startAt: Date().addingTimeInterval(2),
                seekSeconds: GameTiming.seekSeconds,
                searched: searched,
                found: found,
                assistSafe: assistSafeCells(
                    seeker: seeker,
                    spots: spots,
                    found: found,
                    searched: searched,
                    cellCount: hideStart.cellCount
                )
            )
            await send(.seekTurn(turnStart))

            var pick = await collectSeekPick(for: turnStart)
            if let cell = pick, cell < 0 || cell >= hideStart.cellCount || searched.contains(cell) {
                pick = nil
            }
            if let cell = pick, turnStart.assistSafe?[seeker]?.contains(cell) == true {
                // Assisted seekers can't search a square already ruled out.
                pick = nil
            }
            let cell = pick ?? randomUnsearchedCell(
                searched: searched + (turnStart.assistSafe?[seeker] ?? []),
                cellCount: hideStart.cellCount
            )
            searched.append(cell)

            let revealed = spots
                .filter { $0.value == cell && found[$0.key] == nil }
                .map(\.key)
                .sorted()
            for slot in revealed {
                found[slot] = cell
            }

            let hidden = players.filter { found[$0] == nil }
            var roundWinners: [Int] = []
            if hidden.count == 1 {
                roundWinners = hidden
            } else if hidden.isEmpty {
                // The last hiders were all revealed by the same search —
                // they were all "last to be found", so they share the round.
                roundWinners = revealed
            }

            let reveal = SeekReveal(
                round: round,
                turn: turn,
                seeker: seeker,
                cell: cell,
                gridSize: gridSize,
                revealed: revealed,
                searched: searched,
                found: found,
                remainingHidden: hidden,
                roundWinners: roundWinners,
                nextTurnAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.seekRevealSeconds + 2) : nil
            )
            await send(.seekReveal(reveal))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            try? await Task.sleep(for: .seconds(GameTiming.seekRevealSeconds))
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectHideSpots(for hideStart: HideStart, players: [Int]) async -> [Int: Int] {
        let deadline = hideStart.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var spots: [Int: Int] = [:]
        while !Task.isCancelled {
            let missing = players.filter { spots[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map { RecordName.hide(config.gameID, round: hideStart.round, slot: $0) }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .hide(_, let slot, let cell) = message else { continue }
                    spots[slot] = (0..<hideStart.cellCount).contains(cell)
                        ? cell
                        : Int.random(in: 0..<hideStart.cellCount)
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        // Anyone who never picked gets hidden somewhere random.
        for slot in players where spots[slot] == nil {
            spots[slot] = Int.random(in: 0..<hideStart.cellCount)
        }
        return spots
    }

    private func collectSeekPick(for turnStart: SeekTurnStart) async -> Int? {
        let id = RecordName.seek(config.gameID, round: turnStart.round, turn: turnStart.turn, slot: turnStart.seeker)
        let deadline = turnStart.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        while !Task.isCancelled && Date() < deadline {
            if let found = try? await transport.get(ids: [id]),
               let body = found[id],
               let message = try? crypto.open(PlayerMessage.self, from: body),
               case .seek(_, _, _, let cell) = message {
                return cell
            }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return nil
    }

    private func randomUnsearchedCell(searched: [Int], cellCount: Int) -> Int {
        Set(0..<cellCount).subtracting(searched).randomElement() ?? 0
    }

    /// Simplify: rule out squares nobody is hiding in for an assisted
    /// seeker — a few, lots, or (top level) all but the occupied squares
    /// plus a couple of decoys.
    private func assistSafeCells(
        seeker: Int,
        spots: [Int: Int],
        found: [Int: Int],
        searched: [Int],
        cellCount: Int
    ) -> [Int: [Int]]? {
        guard let level = assistLevel(seeker) else { return nil }
        let occupied = Set(spots.filter { found[$0.key] == nil }.map(\.value))
        let empties = (0..<cellCount)
            .filter { !occupied.contains($0) && !searched.contains($0) }
            .shuffled()
        let count: Int
        switch level {
        case .little: count = min(5, empties.count)
        case .big: count = min(10, empties.count)
        case .cheating: count = max(0, empties.count - 2)
        }
        guard count > 0 else { return nil }
        return [seeker: Array(empties.prefix(count)).sorted()]
    }

    // MARK: - Higher or Lower

    /// Matches until someone reaches the target points. Every winner of a
    /// match scores; several players can hit the target together and all
    /// win the round (the game-level tie-break handles the rest).
    private func runHigherLowerRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var deck = Deck()
        var match = 1
        while !Task.isCancelled {
            let matchWinners = await runHigherLowerMatch(
                round: round,
                match: match,
                players: players,
                pointsBefore: points,
                deck: &deck
            )
            for winner in matchWinners {
                points[winner, default: 0] += 1
            }
            let champions = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }
            if !champions.isEmpty {
                return champions
            }
            if match >= GameTiming.maxTurnsPerRound {
                // Safety valve: award the round to whoever leads.
                let best = points.values.max() ?? 0
                let leaders = players.filter { points[$0, default: 0] == best }
                return leaders.isEmpty ? [players.first ?? 1] : leaders
            }
            match += 1
        }
        return [players.first ?? 1]
    }

    /// One elimination match: everyone alive calls the next card higher or
    /// lower; wrong calls are out. A tied rank eliminates nobody. Last one
    /// standing wins — and if the final survivors all fall together, they
    /// were all "last to be eliminated" and all win.
    private func runHigherLowerMatch(
        round: Int,
        match: Int,
        players: [Int],
        pointsBefore: [Int: Int],
        deck: inout Deck
    ) async -> [Int] {
        var alive = players
        var current = deck.draw()
        var step = 1
        while !Task.isCancelled {
            // Pre-drawn so top-level Simplify can whisper the right call.
            let next = deck.draw()
            var assistCorrect: [Int: HigherLowerGuess]?
            let cheats = alive.filter { assistLevel($0) == .cheating }
            if !cheats.isEmpty && next.rank != current.rank {
                let correct: HigherLowerGuess = next.rank > current.rank ? .higher : .lower
                assistCorrect = Dictionary(uniqueKeysWithValues: cheats.map { ($0, correct) })
            }
            let turn = CardTurn(
                round: round,
                match: match,
                step: step,
                card: current,
                alive: alive,
                points: pointsBefore,
                startAt: Date().addingTimeInterval(2),
                guessSeconds: GameTiming.guessSeconds,
                assistCorrect: assistCorrect
            )
            await send(.cardTurn(turn))
            let guesses = await collectGuesses(for: turn)

            var eliminated: [Int] = []
            var isTie = false
            if next.rank == current.rank {
                isTie = true
            } else {
                let correct: HigherLowerGuess = next.rank > current.rank ? .higher : .lower
                eliminated = alive.filter { guesses[$0] != correct }
            }
            let survivors = alive.filter { !eliminated.contains($0) }

            var matchWinners: [Int] = []
            if survivors.count == 1 {
                matchWinners = survivors
            } else if survivors.isEmpty {
                matchWinners = eliminated
            } else if step >= 20 {
                // Safety valve for an absurdly lucky table.
                matchWinners = survivors
            }

            var pointsAfter = pointsBefore
            for winner in matchWinners {
                pointsAfter[winner, default: 0] += 1
            }
            let roundWinners = matchWinners.isEmpty
                ? []
                : players.filter { pointsAfter[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = CardReveal(
                round: round,
                match: match,
                step: step,
                previousCard: current,
                nextCard: next,
                guesses: guesses,
                eliminated: eliminated,
                alive: survivors,
                isTie: isTie,
                matchWinners: matchWinners,
                points: pointsAfter,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.cardRevealSeconds + 2) : nil
            )
            await send(.cardReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.cardRevealSeconds))
            if !matchWinners.isEmpty {
                return matchWinners
            }
            alive = survivors
            current = next
            step += 1
        }
        return []
    }

    private func collectGuesses(for turn: CardTurn) async -> [Int: HigherLowerGuess] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var guesses: [Int: HigherLowerGuess] = [:]
        while !Task.isCancelled {
            let missing = turn.alive.filter { guesses[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.guess(config.gameID, round: turn.round, match: turn.match, step: turn.step, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .guess(_, _, _, let slot, let guess) = message else { continue }
                    guesses[slot] = guess
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        // A silent player gets a random call rather than auto-elimination,
        // so a network blip can't knock someone out.
        for slot in turn.alive where guesses[slot] == nil {
            guesses[slot] = Bool.random() ? .higher : .lower
        }
        return guesses
    }

    // MARK: - Repeat After Me

    /// Matches until someone reaches the target points, exactly like
    /// Higher or Lower — only the elimination test differs.
    private func runRepeatAfterMeRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var match = 1
        while !Task.isCancelled {
            let matchWinners = await runSequenceMatch(round: round, match: match, players: players, pointsBefore: points)
            for winner in matchWinners {
                points[winner, default: 0] += 1
            }
            let champions = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }
            if !champions.isEmpty {
                return champions
            }
            if match >= GameTiming.maxTurnsPerRound {
                let best = points.values.max() ?? 0
                let leaders = players.filter { points[$0, default: 0] == best }
                return leaders.isEmpty ? [players.first ?? 1] : leaders
            }
            match += 1
        }
        return [players.first ?? 1]
    }

    /// One memory match: the sequence grows by one pad each turn and every
    /// player alive must tap it back exactly. A mistake — or no answer at
    /// all — eliminates (this is a skill test, so there is no random-mercy
    /// fallback like Higher or Lower's). Last standing wins; if everyone
    /// left fails the same sequence, they all win.
    private func runSequenceMatch(round: Int, match: Int, players: [Int], pointsBefore: [Int: Int]) async -> [Int] {
        var alive = players
        var sequence = (0..<GameTiming.sequenceStartLength).map { _ in Int.random(in: 0..<4) }
        var step = 1
        while !Task.isCancelled {
            if step > 1 {
                sequence.append(Int.random(in: 0..<4))
            }
            let watchSeconds = 1.0 + Double(sequence.count) * GameTiming.sequenceFlashSeconds + 0.5
            let answerSeconds = max(6.0, Double(sequence.count) * 1.2)
            let turn = SequenceTurn(
                round: round,
                match: match,
                step: step,
                sequence: sequence,
                alive: alive,
                points: pointsBefore,
                startAt: Date().addingTimeInterval(2),
                watchSeconds: watchSeconds,
                answerSeconds: answerSeconds
            )
            await send(.sequenceTurn(turn))
            let answers = await collectSequenceAnswers(for: turn)

            var results: [SequencePlayerResult] = []
            var eliminated: [Int] = []
            for slot in alive {
                let taps = answers[slot]
                let correct = taps == sequence
                if !correct {
                    eliminated.append(slot)
                }
                results.append(SequencePlayerResult(slot: slot, taps: taps, correct: correct))
            }
            let survivors = alive.filter { !eliminated.contains($0) }

            var matchWinners: [Int] = []
            if survivors.count == 1 {
                matchWinners = survivors
            } else if survivors.isEmpty {
                matchWinners = eliminated
            } else if step >= 20 {
                matchWinners = survivors
            }

            var pointsAfter = pointsBefore
            for winner in matchWinners {
                pointsAfter[winner, default: 0] += 1
            }
            let roundWinners = matchWinners.isEmpty
                ? []
                : players.filter { pointsAfter[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = SequenceReveal(
                round: round,
                match: match,
                step: step,
                sequence: sequence,
                results: results,
                eliminated: eliminated,
                alive: survivors,
                matchWinners: matchWinners,
                points: pointsAfter,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.sequenceRevealSeconds + 2) : nil
            )
            await send(.sequenceReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.sequenceRevealSeconds))
            if !matchWinners.isEmpty {
                return matchWinners
            }
            alive = survivors
            step += 1
        }
        return []
    }

    private func collectSequenceAnswers(for turn: SequenceTurn) async -> [Int: [Int]] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var answers: [Int: [Int]] = [:]
        while !Task.isCancelled {
            let missing = turn.alive.filter { answers[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.sequenceAnswer(config.gameID, round: turn.round, match: turn.match, step: turn.step, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .sequenceAnswer(_, _, _, let slot, let taps) = message else { continue }
                    answers[slot] = taps
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return answers
    }

    // MARK: - Lightning

    /// Flash turns until someone reaches the target points. Everyone plays
    /// every flash; the fastest valid tap wins the point (exact ties share).
    private func runLightningRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let startAt = Date().addingTimeInterval(2)
            let wait = Double.random(in: GameTiming.flashWaitMinSeconds...GameTiming.flashWaitMaxSeconds)
            let turnMessage = FlashTurn(
                round: round,
                turn: turn,
                points: points,
                startAt: startAt,
                flashAt: startAt.addingTimeInterval(wait),
                tapWindowSeconds: GameTiming.tapWindowSeconds
            )
            await send(.flashTurn(turnMessage))
            let results = await collectReactions(for: turnMessage, players: players)

            let valid = results.values.filter { !$0.falseStart && $0.elapsedMs != nil }
            let best = valid.compactMap(\.elapsedMs).min()
            let winners = best.map { fastest in
                valid.filter { $0.elapsedMs == fastest }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = FlashReveal(
                round: round,
                turn: turn,
                results: players.compactMap { results[$0] },
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.flashRevealSeconds + 2) : nil
            )
            await send(.flashReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.flashRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectReactions(for turn: FlashTurn, players: [Int]) async -> [Int: FlashResult] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var results: [Int: FlashResult] = [:]
        while !Task.isCancelled {
            let missing = players.filter { results[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.reaction(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .reaction(_, _, let slot, let elapsedMs, let falseStart) = message else { continue }
                    results[slot] = FlashResult(slot: slot, elapsedMs: elapsedMs, falseStart: falseStart)
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        for slot in players where results[slot] == nil {
            results[slot] = FlashResult(slot: slot, elapsedMs: nil, falseStart: false)
        }
        return results
    }

    // MARK: - Put Your Finger On It

    /// One region per round; each turn asks for a place in it. Closest pin
    /// to the capital takes the point.
    private func runFingerRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        let region = FingerAtlas.regions.randomElement() ?? FingerAtlas.regions[0]
        var usedPlaces: Set<String> = []
        var turn = 1
        while !Task.isCancelled {
            let fresh = region.places.filter { !usedPlaces.contains($0.name) }
            guard let place = (fresh.randomElement() ?? region.places.randomElement()) else {
                return [players.first ?? 1]
            }
            usedPlaces.insert(place.name)
            var assistHints: [Int: FingerHint] = [:]
            for slot in players {
                guard let level = assistLevel(slot) else { continue }
                let spanKm = min(region.spanLat, region.spanLon) * 111.0
                let radiusKm: Double
                switch level {
                case .little: radiusKm = spanKm * 0.22
                case .big: radiusKm = spanKm * 0.12
                case .cheating: radiusKm = spanKm * 0.05
                }
                // Shove the circle's centre off the capital so the middle
                // of the glow isn't the answer.
                let center = DirectionMath.destination(
                    from: place.coordinate,
                    bearing: Double.random(in: 0..<360),
                    distanceMeters: Double.random(in: 0...(radiusKm * 600))
                )
                assistHints[slot] = FingerHint(center: center, radiusKm: radiusKm)
            }
            let turnMessage = FingerTurn(
                round: round,
                turn: turn,
                regionName: region.name,
                regionCenter: region.center,
                regionSpanLat: region.spanLat,
                regionSpanLon: region.spanLon,
                placeName: place.name,
                points: points,
                startAt: Date().addingTimeInterval(2),
                guessSeconds: GameTiming.fingerGuessSeconds,
                assistHints: assistHints.isEmpty ? nil : assistHints
            )
            await send(.fingerTurn(turnMessage))
            let guesses = await collectFingerGuesses(for: turnMessage, players: players)

            var outcomes: [FingerOutcome] = []
            for slot in players {
                let coordinate = guesses[slot]
                let distanceKm = coordinate.map {
                    DirectionMath.distanceMeters(from: $0, to: place.coordinate) / 1000
                }
                outcomes.append(FingerOutcome(slot: slot, coordinate: coordinate, distanceKm: distanceKm))
            }
            let best = outcomes.compactMap(\.distanceKm).min()
            let winners = best.map { closest in
                outcomes.filter { $0.distanceKm == closest }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = FingerReveal(
                round: round,
                turn: turn,
                regionName: region.name,
                placeName: place.name,
                capitalName: place.capital,
                target: place.coordinate,
                outcomes: outcomes,
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.fingerRevealSeconds + 2) : nil
            )
            await send(.fingerReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.fingerRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectFingerGuesses(for turn: FingerTurn, players: [Int]) async -> [Int: Coordinate] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var guesses: [Int: Coordinate] = [:]
        while !Task.isCancelled {
            let missing = players.filter { guesses[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.fingerGuess(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .fingerGuess(_, _, let slot, let coordinate) = message else { continue }
                    guesses[slot] = coordinate
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return guesses
    }

    // MARK: - Ten Seconds

    /// Turns until someone reaches the target points. Everyone counts in
    /// their head against a shared start timestamp and taps; the closest
    /// to the (varying) target wins the turn, exact ties share.
    private func runClockRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let target = Double(Int.random(in: 7...15))
            let turnMessage = ClockTurn(
                round: round,
                turn: turn,
                points: points,
                startAt: Date().addingTimeInterval(2),
                targetSeconds: target,
                visibleSeconds: GameTiming.clockVisibleSeconds,
                maxSeconds: target + 8
            )
            await send(.clockTurn(turnMessage))
            let taps = await collectClockTaps(for: turnMessage, players: players)

            var results: [ClockResult] = []
            for slot in players {
                let elapsed = taps[slot]
                let error = elapsed.map { abs($0 - Int(target * 1000)) }
                results.append(ClockResult(slot: slot, elapsedMs: elapsed, errorMs: error))
            }
            let best = results.compactMap(\.errorMs).min()
            let winners = best.map { closest in
                results.filter { $0.errorMs == closest }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = ClockReveal(
                round: round,
                turn: turn,
                targetSeconds: target,
                results: results,
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.clockRevealSeconds + 2) : nil
            )
            await send(.clockReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.clockRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectClockTaps(for turn: ClockTurn, players: [Int]) async -> [Int: Int] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var taps: [Int: Int] = [:]
        while !Task.isCancelled {
            let missing = players.filter { taps[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.clockTap(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .clockTap(_, _, let slot, let elapsedMs) = message else { continue }
                    taps[slot] = elapsedMs
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return taps
    }

    // MARK: - Push Your Luck

    /// Runs of dice until someone banks the target. The round finishes the
    /// current run before crowning, so simultaneous crossers share it.
    private func runDiceRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var banks: [Int: Int] = [:]
        var run = 1
        while !Task.isCancelled {
            await runDiceRun(round: round, run: run, players: players, banks: &banks)
            let champions = players.filter { banks[$0, default: 0] >= GameTiming.diceBankTarget }
            if !champions.isEmpty {
                return champions
            }
            if run >= GameTiming.diceMaxRuns {
                let best = banks.values.max() ?? 0
                let leaders = players.filter { banks[$0, default: 0] == best }
                return leaders.isEmpty ? [players.first ?? 1] : leaders
            }
            run += 1
        }
        return [players.first ?? 1]
    }

    private func runDiceRun(round: Int, run: Int, players: [Int], banks: inout [Int: Int]) async {
        var riders = players
        // The run opens with one free, never-skull die so the first choice
        // is a real one.
        var pot = Int.random(in: 2...6)
        var step = 1
        while !Task.isCancelled {
            // Pre-rolled so top-level Simplify can peek at what's coming.
            let prerolled = Int.random(in: 1...6)
            var assistPeek: [Int: Bool]?
            let peekers = riders.filter { assistLevel($0) == .cheating }
            if !peekers.isEmpty {
                assistPeek = Dictionary(uniqueKeysWithValues: peekers.map { ($0, prerolled == 1) })
            }
            let stepMessage = DiceStep(
                round: round,
                run: run,
                step: step,
                pot: pot,
                riders: riders,
                banks: banks,
                startAt: Date().addingTimeInterval(2),
                chooseSeconds: GameTiming.diceChooseSeconds,
                assistPeek: assistPeek
            )
            await send(.diceStep(stepMessage))
            let choices = await collectDiceChoices(for: stepMessage)

            // Silence defaults to banking — a network blip shouldn't bust you.
            let bankedNow = riders.filter { choices[$0] != true }
            for slot in bankedNow {
                banks[slot, default: 0] += pot
            }
            let stillRiding = riders.filter { choices[$0] == true }

            var die: Int?
            var isSkull = false
            var potAfter = pot
            var runOver = false
            if stillRiding.isEmpty {
                runOver = true
            } else {
                let drawn = prerolled
                die = drawn
                if drawn == 1 {
                    isSkull = true
                    potAfter = 0
                    runOver = true
                } else {
                    potAfter = pot + drawn
                }
            }

            let champions = players.filter { banks[$0, default: 0] >= GameTiming.diceBankTarget }
            let roundWinners = runOver ? champions : []
            let reveal = DiceReveal(
                round: round,
                run: run,
                step: step,
                die: die,
                isSkull: isSkull,
                potBefore: pot,
                potAfter: potAfter,
                choices: Dictionary(uniqueKeysWithValues: riders.map { ($0, choices[$0] == true) }),
                bankedNow: bankedNow,
                riders: stillRiding,
                banks: banks,
                runOver: runOver,
                roundWinners: roundWinners,
                nextAt: (runOver && !roundWinners.isEmpty) ? nil : Date().addingTimeInterval(GameTiming.diceRevealSeconds + 2)
            )
            await send(.diceReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.diceRevealSeconds))
            if runOver {
                return
            }
            pot = potAfter
            riders = stillRiding
            step += 1
        }
    }

    private func collectDiceChoices(for step: DiceStep) async -> [Int: Bool] {
        let deadline = step.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var choices: [Int: Bool] = [:]
        while !Task.isCancelled {
            let missing = step.riders.filter { choices[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.dice(config.gameID, round: step.round, run: step.run, step: step.step, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .dice(_, _, _, let slot, let push) = message else { continue }
                    choices[slot] = push
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return choices
    }

    // MARK: - Gold Rush

    /// Turns of secret picks on a shared coin board. Unique picks pocket
    /// their coins, collisions score nothing; first to the target wins the
    /// round (shared if several cross together).
    private func runGoldRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var totals: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let turnMessage = GoldTurn(
                round: round,
                turn: turn,
                gridSize: 5,
                coins: Self.makeGoldBoard(),
                totals: totals,
                startAt: Date().addingTimeInterval(2),
                pickSeconds: GameTiming.goldPickSeconds
            )
            await send(.goldTurn(turnMessage))
            let picks = await collectGoldPicks(for: turnMessage, players: players)

            var pickCounts: [Int: Int] = [:]
            for cell in picks.values {
                pickCounts[cell, default: 0] += 1
            }
            let clashes = pickCounts.filter { $0.value > 1 }.map(\.key).sorted()
            var gains: [Int: Int] = [:]
            for (slot, cell) in picks where pickCounts[cell] == 1 {
                let value = turnMessage.coins.indices.contains(cell) ? turnMessage.coins[cell] : 0
                gains[slot] = value
                totals[slot, default: 0] += value
            }
            let roundWinners = players.filter { totals[$0, default: 0] >= GameTiming.goldTarget }

            let reveal = GoldReveal(
                round: round,
                turn: turn,
                gridSize: turnMessage.gridSize,
                coins: turnMessage.coins,
                picks: picks,
                clashes: clashes,
                gains: gains,
                totals: totals,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.goldRevealSeconds + 2) : nil
            )
            await send(.goldReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.goldRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.goldMaxTurns {
                let best = totals.values.max() ?? 0
                let leaders = players.filter { totals[$0, default: 0] == best }
                return leaders.isEmpty ? [players.first ?? 1] : leaders
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    /// One juicy square, a couple of good ones, and a long tail — the same
    /// spread every turn, shuffled into fresh positions.
    private static func makeGoldBoard() -> [Int] {
        let values = [10, 8, 6, 6, 5, 5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1]
        return values.shuffled()
    }

    private func collectGoldPicks(for turn: GoldTurn, players: [Int]) async -> [Int: Int] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var picks: [Int: Int] = [:]
        // Simplify (levels 2–3): these players see others' picks land live.
        let watchers = players.filter { slot in
            guard let level = assistLevel(slot) else { return false }
            return level >= .big
        }
        var announced = 0
        while !Task.isCancelled {
            let missing = players.filter { picks[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.goldPick(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .goldPick(_, _, let slot, let cell) = message,
                          (0..<turn.cellCount).contains(cell) else { continue }
                    picks[slot] = cell
                }
            }
            // Re-publish the turn with the taken squares whenever new picks
            // arrive and an assisted player is still choosing.
            if picks.count > announced, watchers.contains(where: { picks[$0] == nil }) {
                announced = picks.count
                var updated = turn
                updated.assistTaken = Dictionary(uniqueKeysWithValues: watchers.map { slot in
                    (slot, picks.filter { $0.key != slot }.map(\.value).sorted())
                })
                await send(.goldTurn(updated))
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return picks
    }

    // MARK: - Eyeball It

    private func runEyeballRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let turnMessage = EyeballTurn(
                round: round,
                turn: turn,
                points: points,
                startAt: Date().addingTimeInterval(2),
                count: Int.random(in: 40...150),
                seed: UInt64.random(in: UInt64.min...UInt64.max),
                visibleSeconds: GameTiming.eyeballVisibleSeconds,
                guessSeconds: GameTiming.eyeballGuessSeconds
            )
            await send(.eyeballTurn(turnMessage))
            let guesses = await collectEyeballGuesses(for: turnMessage, players: players)

            var results: [EyeballResult] = []
            for slot in players {
                let guess = guesses[slot]
                results.append(EyeballResult(
                    slot: slot,
                    guess: guess,
                    error: guess.map { abs($0 - turnMessage.count) }
                ))
            }
            let best = results.compactMap(\.error).min()
            let winners = best.map { closest in
                results.filter { $0.error == closest }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = EyeballReveal(
                round: round,
                turn: turn,
                count: turnMessage.count,
                results: results,
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.eyeballRevealSeconds + 2) : nil
            )
            await send(.eyeballReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.eyeballRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectEyeballGuesses(for turn: EyeballTurn, players: [Int]) async -> [Int: Int] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var guesses: [Int: Int] = [:]
        while !Task.isCancelled {
            let missing = players.filter { guesses[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.eyeball(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .eyeball(_, _, let slot, let guess) = message else { continue }
                    guesses[slot] = guess
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return guesses
    }

    // MARK: - Perfect Circle

    /// Players submit their stroke; the host scores it authoritatively.
    private func runCircleRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let turnMessage = CircleTurn(
                round: round,
                turn: turn,
                points: points,
                startAt: Date().addingTimeInterval(2),
                drawSeconds: GameTiming.circleDrawSeconds
            )
            await send(.circleTurn(turnMessage))
            let paths = await collectCirclePaths(for: turnMessage, players: players)

            var results: [CircleResult] = []
            for slot in players {
                let path = paths[slot]
                var score = path.flatMap { CircleScore.evaluate(flat: $0) }
                if let raw = score, assistLevel(slot) == .cheating {
                    // Simplify (top level): a friendly nudge on the score,
                    // on top of the guide ring their device draws.
                    score = min(100, ((raw + 7) * 10).rounded() / 10)
                }
                results.append(CircleResult(
                    slot: slot,
                    score: score,
                    path: path
                ))
            }
            let best = results.compactMap(\.score).max()
            let winners = best.map { top in
                results.filter { $0.score == top }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = CircleReveal(
                round: round,
                turn: turn,
                results: results,
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.circleRevealSeconds + 2) : nil
            )
            await send(.circleReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.circleRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectCirclePaths(for turn: CircleTurn, players: [Int]) async -> [Int: [Double]] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var paths: [Int: [Double]] = [:]
        while !Task.isCancelled {
            let missing = players.filter { paths[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.circleDraw(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .circleDraw(_, _, let slot, let path) = message else { continue }
                    paths[slot] = path
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return paths
    }

    // MARK: - Sort Circuit

    private func runSortRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let turnMessage = SortTurn(
                round: round,
                turn: turn,
                points: points,
                startAt: Date().addingTimeInterval(2),
                seed: UInt64.random(in: UInt64.min...UInt64.max),
                tileCount: 9,
                maxSeconds: GameTiming.sortMaxSeconds
            )
            await send(.sortTurn(turnMessage))
            let times = await collectSortTimes(for: turnMessage, players: players)

            var results: [SortResult] = []
            for slot in players {
                if let (elapsedMs, mistakes) = times[slot] {
                    results.append(SortResult(slot: slot, elapsedMs: elapsedMs, mistakes: mistakes))
                } else {
                    results.append(SortResult(slot: slot, elapsedMs: nil, mistakes: 0))
                }
            }
            let best = results.compactMap(\.elapsedMs).min()
            let winners = best.map { fastest in
                results.filter { $0.elapsedMs == fastest }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = SortReveal(
                round: round,
                turn: turn,
                results: results,
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.sortRevealSeconds + 2) : nil
            )
            await send(.sortReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.sortRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectSortTimes(for turn: SortTurn, players: [Int]) async -> [Int: (Int, Int)] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var times: [Int: (Int, Int)] = [:]
        while !Task.isCancelled {
            let missing = players.filter { times[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.sortTime(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .sortTime(_, _, let slot, let elapsedMs, let mistakes) = message else { continue }
                    times[slot] = (elapsedMs, mistakes)
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return times
    }

    // MARK: - Steady Hand

    /// Turns until someone reaches the target points. The ring's drift is
    /// seeded so every device shows the identical path; survival time is
    /// measured locally against the shared start, longest hold wins.
    private func runSteadyRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let turnMessage = SteadyTurn(
                round: round,
                turn: turn,
                points: points,
                startAt: Date().addingTimeInterval(3),
                seed: UInt64.random(in: UInt64.min...UInt64.max),
                maxSeconds: GameTiming.steadyMaxSeconds
            )
            await send(.steadyTurn(turnMessage))
            let times = await collectSteadyTimes(for: turnMessage, players: players)

            var results: [SteadyResult] = []
            for slot in players {
                results.append(SteadyResult(slot: slot, survivedMs: times[slot]))
            }
            let best = results.compactMap(\.survivedMs).max()
            let winners = best.map { longest in
                results.filter { $0.survivedMs == longest }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = SteadyReveal(
                round: round,
                turn: turn,
                results: results,
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.steadyRevealSeconds + 2) : nil
            )
            await send(.steadyReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.steadyRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    /// Everyone's run ends at their own moment, so the collection window
    /// spans the whole turn — but once everyone has reported, it moves on.
    private func collectSteadyTimes(for turn: SteadyTurn, players: [Int]) async -> [Int: Int] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var times: [Int: Int] = [:]
        while !Task.isCancelled {
            let missing = players.filter { times[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.steadyTime(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .steadyTime(_, _, let slot, let survivedMs) = message else { continue }
                    times[slot] = max(0, min(survivedMs, Int(turn.maxSeconds * 1000)))
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return times
    }

    // MARK: - Showdown

    /// Rock-paper-scissors against the whole table: each turn everyone
    /// throws in secret and you score a win per player you beat. First to
    /// the target total takes the round (shared if several cross together).
    private func runShowdownRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var totals: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let turnMessage = ShowdownTurn(
                round: round,
                turn: turn,
                totals: totals,
                startAt: Date().addingTimeInterval(2),
                throwSeconds: GameTiming.showdownThrowSeconds
            )
            await send(.showdownTurn(turnMessage))
            let thrown = await collectShowdownThrows(for: turnMessage, players: players)

            var gains: [Int: Int] = [:]
            for slot in players {
                let beaten = players.filter { other in
                    guard other != slot else { return false }
                    guard let mine = thrown[slot] else { return false }
                    guard let theirs = thrown[other] else { return true }
                    return mine.beats(theirs)
                }.count
                gains[slot] = beaten
                totals[slot, default: 0] += beaten
            }
            let best = gains.values.max() ?? 0
            let winners = best > 0 ? players.filter { gains[$0] == best } : []
            let roundWinners = players.filter { totals[$0, default: 0] >= GameTiming.showdownTarget }

            let reveal = ShowdownReveal(
                round: round,
                turn: turn,
                thrown: thrown,
                gains: gains,
                totals: totals,
                winners: winners,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.showdownRevealSeconds + 2) : nil
            )
            await send(.showdownReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.showdownRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.showdownMaxTurns {
                let top = totals.values.max() ?? 0
                let leaders = players.filter { totals[$0, default: 0] == top }
                return leaders.isEmpty ? [players.first ?? 1] : leaders
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectShowdownThrows(for turn: ShowdownTurn, players: [Int]) async -> [Int: RPSThrow] {
        let deadline = turn.deadline.addingTimeInterval(GameTiming.answerGraceSeconds)
        var thrown: [Int: RPSThrow] = [:]
        // Simplify (levels 2–3): these players see others' throws live.
        let watchers = players.filter { slot in
            guard let level = assistLevel(slot) else { return false }
            return level >= .big
        }
        var announced = 0
        while !Task.isCancelled {
            let missing = players.filter { thrown[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.showdownThrow(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .showdownThrow(_, _, let slot, let throwing) = message else { continue }
                    thrown[slot] = throwing
                }
            }
            // Re-publish the turn with what's been thrown whenever new
            // throws arrive and an assisted player is still choosing.
            if thrown.count > announced, watchers.contains(where: { thrown[$0] == nil }) {
                announced = thrown.count
                var updated = turn
                updated.assistThrown = Dictionary(uniqueKeysWithValues: watchers.map { slot in
                    (slot, thrown.filter { $0.key != slot })
                })
                await send(.showdownTurn(updated))
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return thrown
    }

    // MARK: - Tap Frenzy

    /// Turns until someone reaches the target points: a fixed window, most
    /// taps wins. Counts are measured locally against the shared start.
    private func runFrenzyRound(round: Int) async -> [Int] {
        let players = joined.sorted()
        var points: [Int: Int] = [:]
        var turn = 1
        while !Task.isCancelled {
            let turnMessage = FrenzyTurn(
                round: round,
                turn: turn,
                points: points,
                startAt: Date().addingTimeInterval(3),
                tapSeconds: GameTiming.frenzyTapSeconds
            )
            await send(.frenzyTurn(turnMessage))
            let counts = await collectFrenzyTaps(for: turnMessage, players: players)

            var results: [FrenzyResult] = []
            for slot in players {
                results.append(FrenzyResult(slot: slot, taps: counts[slot]))
            }
            let best = results.compactMap(\.taps).max()
            let winners = best.map { most in
                results.filter { $0.taps == most }.map(\.slot).sorted()
            } ?? []
            for winner in winners {
                points[winner, default: 0] += 1
            }
            let roundWinners = players.filter { points[$0, default: 0] >= GameTiming.pointsToWinRound }

            let reveal = FrenzyReveal(
                round: round,
                turn: turn,
                results: results,
                winners: winners,
                points: points,
                roundWinners: roundWinners,
                nextAt: roundWinners.isEmpty ? Date().addingTimeInterval(GameTiming.frenzyRevealSeconds + 2) : nil
            )
            await send(.frenzyReveal(reveal))
            try? await Task.sleep(for: .seconds(GameTiming.frenzyRevealSeconds))
            if !roundWinners.isEmpty {
                return roundWinners
            }
            if turn >= GameTiming.maxTurnsPerRound {
                return pointLeaders(points: points, players: players)
            }
            turn += 1
        }
        return [players.first ?? 1]
    }

    private func collectFrenzyTaps(for turn: FrenzyTurn, players: [Int]) async -> [Int: Int] {
        // Simplify can stretch a player's window, so wait for the longest.
        let deadline = turn.deadline.addingTimeInterval(
            GameTiming.frenzyMaxAssistExtraSeconds + GameTiming.answerGraceSeconds
        )
        var counts: [Int: Int] = [:]
        while !Task.isCancelled {
            let missing = players.filter { counts[$0] == nil }
            if missing.isEmpty { break }
            let ids = missing.map {
                RecordName.frenzyTaps(config.gameID, round: turn.round, turn: turn.turn, slot: $0)
            }
            if let found = try? await transport.get(ids: ids) {
                for body in found.values {
                    guard let message = try? crypto.open(PlayerMessage.self, from: body),
                          case .frenzyTaps(_, _, let slot, let taps) = message else { continue }
                    counts[slot] = max(0, taps)
                }
            }
            if Date() > deadline { break }
            try? await Task.sleep(for: .seconds(0.75))
        }
        return counts
    }

    private func pointLeaders(points: [Int: Int], players: [Int]) -> [Int] {
        let best = points.values.max() ?? 0
        let leaders = players.filter { points[$0, default: 0] == best }
        return leaders.isEmpty ? [players.first ?? 1] : leaders
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
