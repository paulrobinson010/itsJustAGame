import SwiftUI

/// Full-screen container for an active game. The session and engine live
/// in AppModel's GameStack — this view only renders whichever phase the
/// game is in, cross-fading between phases.
struct GameScreen: View {
    let saved: SavedGame
    let model: AppModel
    let stack: GameStack
    @State private var showWelcome: Bool
    @State private var showLeaveConfirm = false

    private var session: GameSession { stack.session }
    private var engine: HostEngine? { stack.engine }

    init(saved: SavedGame, model: AppModel, stack: GameStack) {
        self.saved = saved
        self.model = model
        self.stack = stack
        _showWelcome = State(initialValue: saved.needsWelcome == true)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                content
                    .id(contentKey)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    // Comfortable column on iPad instead of edge-to-edge.
                    .frame(maxWidth: 700)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            // No cross-fades while the initial replay drains the stream.
            .animation(session.caughtUp ? .easeInOut(duration: 0.35) : nil, value: contentKey)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved.practiceGame != nil ? "End" : "Leave") {
                        if saved.practiceGame != nil {
                            // Practice just ends — nothing to warn about,
                            // nothing was ever saved.
                            leaveAndForget()
                        } else {
                            showLeaveConfirm = true
                        }
                    }
                }
            }
            .confirmationDialog("Leave this game?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
                Button("Leave and remove from this device", role: .destructive) {
                    leaveAndForget()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(saved.isHost
                     ? "You're the host — the game can't continue without this device."
                     : "This clears the game from your phone. You'd need your invite link to rejoin.")
            }
            .safeAreaInset(edge: .bottom) {
                if let error = session.lastError ?? engine?.lastError {
                    Text(error)
                        .font(Theme.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
        }
        // No start/stop here: the stack's loops are owned by AppModel and
        // are already running before this screen appears. A view must
        // never drive game-loop lifecycle — killing loops from a spurious
        // disappear was exactly how games froze.
        .onChange(of: session.phase) { _, newPhase in
            playSound(for: newPhase)
            if case .gameEnd(let winner) = newPhase, saved.summary == nil, let config = session.config {
                model.store.recordSummary(
                    GameSummary(
                        winner: winner,
                        roundsWon: session.roundsWon,
                        players: config.players,
                        roundsToWin: config.roundsToWin
                    ),
                    for: saved
                )
            }
        }
        // The host's rematch shows up as a request on the end screens —
        // players join by tapping accept, never automatically.
    }

    @ViewBuilder
    private var content: some View {
        if let summary = saved.summary {
            // A finished game reopens as its result, never a replay.
            FinishedGameView(
                session: session,
                summary: summary,
                onClose: { close() },
                onPlayAgain: saved.isHost ? { hostRematch() } : nil,
                onJoinRematch: saved.isHost ? nil : { joinRematch($0) }
            )
        } else if showWelcome {
            WelcomeView(session: session) {
                showWelcome = false
                model.store.markWelcomed(saved)
            }
        } else {
            phaseContent
        }
    }

    /// Stable per-phase identity: changes only when the game moves on, not
    /// on every state tweak inside a phase, so in-phase view state (drag
    /// positions, selections) survives.
    private var contentKey: String {
        guard saved.summary == nil else { return "finished" }
        guard !showWelcome else { return "welcome" }
        switch session.phase {
        case .lobby: return "lobby"
        case .wheel(let round, _, _): return "wheel\(round)"
        case .roundIntro(let round, _): return "intro\(round)"
        case .turn(let turnStart): return "turn\(turnStart.round)-\(turnStart.turn)"
        case .reveal(let reveal): return "reveal\(reveal.round)-\(reveal.turn)"
        case .hiding(let hideStart): return "hide\(hideStart.round)"
        case .seekTurn(let turnStart): return "seek\(turnStart.round)-\(turnStart.turn)"
        case .seekReveal(let reveal): return "seekreveal\(reveal.round)-\(reveal.turn)"
        case .cardGuess(let turn): return "cardguess\(turn.round)-\(turn.match)-\(turn.step)"
        case .cardReveal(let reveal): return "cardreveal\(reveal.round)-\(reveal.match)-\(reveal.step)"
        case .sequenceTurn(let turn): return "seqturn\(turn.round)-\(turn.match)-\(turn.step)"
        case .sequenceReveal(let reveal): return "seqreveal\(reveal.round)-\(reveal.match)-\(reveal.step)"
        case .flashTurn(let turn): return "flash\(turn.round)-\(turn.turn)"
        case .flashReveal(let reveal): return "flashreveal\(reveal.round)-\(reveal.turn)"
        case .fingerTurn(let turn): return "finger\(turn.round)-\(turn.turn)"
        case .fingerReveal(let reveal): return "fingerreveal\(reveal.round)-\(reveal.turn)"
        case .clockTurn(let turn): return "clock\(turn.round)-\(turn.turn)"
        case .clockReveal(let reveal): return "clockreveal\(reveal.round)-\(reveal.turn)"
        case .diceStep(let step): return "dice\(step.round)-\(step.run)-\(step.step)"
        case .diceReveal(let reveal): return "dicereveal\(reveal.round)-\(reveal.run)-\(reveal.step)"
        case .goldTurn(let turn): return "gold\(turn.round)-\(turn.turn)"
        case .goldReveal(let reveal): return "goldreveal\(reveal.round)-\(reveal.turn)"
        case .eyeballTurn(let turn): return "eyeball\(turn.round)-\(turn.turn)"
        case .eyeballReveal(let reveal): return "eyeballreveal\(reveal.round)-\(reveal.turn)"
        case .circleTurn(let turn): return "circle\(turn.round)-\(turn.turn)"
        case .circleReveal(let reveal): return "circlereveal\(reveal.round)-\(reveal.turn)"
        case .sortTurn(let turn): return "sort\(turn.round)-\(turn.turn)"
        case .sortReveal(let reveal): return "sortreveal\(reveal.round)-\(reveal.turn)"
        case .steadyTurn(let turn): return "steady\(turn.round)-\(turn.turn)"
        case .steadyReveal(let reveal): return "steadyreveal\(reveal.round)-\(reveal.turn)"
        case .showdownTurn(let turn): return "showdown\(turn.round)-\(turn.turn)"
        case .showdownReveal(let reveal): return "showdownreveal\(reveal.round)-\(reveal.turn)"
        case .frenzyTurn(let turn): return "frenzy\(turn.round)-\(turn.turn)"
        case .frenzyReveal(let reveal): return "frenzyreveal\(reveal.round)-\(reveal.turn)"
        case .roundEnd(let round, _): return "roundend\(round)"
        case .tieBreak: return "tiebreak"
        case .gameEnd: return "gameend"
        }
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
        case .roundEnd(let round, let winners):
            RoundEndView(session: session, round: round, winners: winners)
        case .tieBreak(let candidates, let winner, let spinSeconds):
            TieBreakView(session: session, candidates: candidates, winner: winner, spinSeconds: spinSeconds)
        case .gameEnd(let winner):
            GameEndView(
                session: session,
                winner: winner,
                onClose: { close() },
                onHostRematch: saved.isHost ? { hostRematch() } : nil,
                onJoinRematch: saved.isHost ? nil : { joinRematch($0) }
            )
        }
    }

    /// One place decides what each phase sounds like. Muted while the
    /// initial replay catches up and for reopened finished games.
    private func playSound(for phase: GamePhase) {
        guard session.caughtUp, saved.summary == nil else { return }
        switch phase {
        case .reveal(let reveal):
            SoundPlayer.shared.play(reveal.winner != nil ? .point : .lose)
        case .seekReveal(let reveal):
            SoundPlayer.shared.play(reveal.revealed.isEmpty ? .lose : .point)
        case .cardReveal(let reveal):
            if reveal.isTie {
                SoundPlayer.shared.play(.lockin)
            } else {
                SoundPlayer.shared.play(reveal.eliminated.isEmpty ? .point : .lose)
            }
        case .sequenceReveal(let reveal):
            SoundPlayer.shared.play(reveal.eliminated.isEmpty ? .point : .lose)
        case .flashReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .fingerReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .clockReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .diceReveal(let reveal):
            if reveal.wheelIndex != nil {
                // The reveal spins its own wheel — clicks and the outcome
                // sound come from it, after the landing.
                break
            }
            if reveal.isSkull {
                SoundPlayer.shared.play(.lose)
            } else if reveal.runOver {
                SoundPlayer.shared.play(.point)
            } else {
                SoundPlayer.shared.play(.tick)
            }
        case .goldReveal(let reveal):
            if (reveal.gains[session.mySlot] ?? 0) > 0 {
                SoundPlayer.shared.play(.point)
            } else if reveal.picks[session.mySlot] != nil {
                SoundPlayer.shared.play(.lose)
            } else {
                SoundPlayer.shared.play(.tick)
            }
        case .eyeballReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .circleReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .sortReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .steadyReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .showdownReveal(let reveal):
            if (reveal.gains[session.mySlot] ?? 0) > 0 {
                SoundPlayer.shared.play(.point)
            } else if reveal.thrown[session.mySlot] != nil {
                SoundPlayer.shared.play(.lose)
            } else {
                SoundPlayer.shared.play(.tick)
            }
        case .frenzyReveal(let reveal):
            SoundPlayer.shared.play(reveal.winners.isEmpty ? .lose : .point)
        case .roundEnd:
            SoundPlayer.shared.play(.roundwin)
        case .gameEnd:
            SoundPlayer.shared.play(.fanfare)
        default:
            break
        }
    }

    private func close() {
        model.activeGame = nil
    }

    /// Leave must absolutely clear any game state: remove the saved game
    /// (and its key) from this device. Clearing activeGame stops the
    /// loops via AppModel.syncStack.
    private func leaveAndForget() {
        model.store.remove(saved)
        model.activeGame = nil
    }

    private func hostRematch() {
        guard let engine else { return }
        if let invite = engine.existingRematch {
            // This game already has a rematch — reopen it, never mint another.
            model.adoptRematch(invite, from: saved, open: true)
            return
        }
        Task {
            guard var newSaved = await engine.announceRematch() else { return }
            newSaved.inviteeAddresses = saved.inviteeAddresses
            model.store.add(newSaved)
            model.activeGame = newSaved
        }
    }

    private func joinRematch(_ invite: RematchInvite) {
        model.adoptRematch(invite, from: saved, open: true)
    }
}

/// A finished game reopened later: the stored result, standings, and (for
/// the host) a one-tap fresh game with the same crew. The session still
/// replays quietly underneath so a rematch someone already started is
/// discovered and joined automatically.
struct FinishedGameView: View {
    let session: GameSession
    let summary: GameSummary
    var onClose: () -> Void
    var onPlayAgain: (() -> Void)?
    var onJoinRematch: ((RematchInvite) -> Void)?

    @State private var playAgainTapped = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🏆")
                .font(.system(size: 64))
            Text("\(summary.name(summary.winner)) won this game")
                .font(Theme.display(30))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            standings
            VStack(spacing: 12) {
                if let invite = session.pendingRematch, onPlayAgain == nil {
                    Text("🔁 \(session.name(1)) wants a rematch!")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.magenta)
                    Button {
                        onJoinRematch?(invite)
                    } label: {
                        Label("Join the rematch", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.magenta))
                } else if let onPlayAgain {
                    Button {
                        playAgainTapped = true
                        onPlayAgain()
                        Task {
                            // If announcing failed (offline blip), come back
                            // to life so it can be tried again.
                            try? await Task.sleep(for: .seconds(6))
                            playAgainTapped = false
                        }
                    } label: {
                        Label("Play again — same crew", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(playAgainTapped)
                }
                Button {
                    onClose()
                } label: {
                    Text("Back to home")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private var standings: some View {
        VStack(spacing: 14) {
            ForEach(summary.players) { player in
                HStack(spacing: 10) {
                    Circle()
                        .fill(player.color)
                        .frame(width: 10, height: 10)
                    Text(player.name)
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    Spacer()
                    let won = summary.roundsWon[player.slot, default: 0]
                    let total = max(summary.roundsToWin, won)
                    HStack(spacing: 5) {
                        ForEach(0..<total, id: \.self) { index in
                            Circle()
                                .fill(index < won ? player.color : Theme.quietFill)
                                .overlay(Circle().stroke(Theme.hairline, lineWidth: index < won ? 0 : 1))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
        .card()
        .padding(.horizontal, 24)
    }
}

/// Quiet player chips with live points. The local player gets a hairline
/// accent ring rather than a louder fill.
struct ScoreBar: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 8) {
            ForEach(session.players) { player in
                HStack(spacing: 6) {
                    Circle()
                        .fill(player.color)
                        .frame(width: 8, height: 8)
                    Text(player.name)
                        .font(Theme.caption)
                        .lineLimit(1)
                    Text("\(session.points[player.slot, default: 0])")
                        .font(Theme.caption.weight(.bold).monospacedDigit())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.quietFill, in: Capsule())
                .overlay(
                    Capsule().stroke(
                        player.slot == session.mySlot ? Color.accentColor.opacity(0.5) : .clear,
                        lineWidth: 1.5
                    )
                )
            }
        }
        .padding(.horizontal)
    }
}

struct RoundIntroView: View {
    let round: Int
    let game: MiniGameType

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Round \(round)")
                .font(Theme.kicker)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            ZStack {
                Circle()
                    .fill(Theme.quietFill)
                    .frame(width: 120, height: 120)
                Image(systemName: game.iconName)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(game.displayName)
                .font(Theme.display(34))
                .multilineTextAlignment(.center)
            Text(game.introText)
                .font(Theme.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
            Spacer()
        }
    }
}

/// Rounds won per player, as filled progress dots out of the target.
struct RoundStandingsView: View {
    let session: GameSession

    var body: some View {
        VStack(spacing: 14) {
            ForEach(session.players) { player in
                HStack(spacing: 10) {
                    Circle()
                        .fill(player.color)
                        .frame(width: 10, height: 10)
                    Text(player.name)
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    Spacer()
                    let won = session.roundsWon[player.slot, default: 0]
                    let total = max(session.config?.roundsToWin ?? 1, won)
                    HStack(spacing: 5) {
                        ForEach(0..<total, id: \.self) { index in
                            Circle()
                                .fill(index < won ? player.color : Theme.quietFill)
                                .overlay(Circle().stroke(Theme.hairline, lineWidth: index < won ? 0 : 1))
                                .frame(width: 8, height: 8)
                        }
                    }
                }
            }
        }
        .card()
        .padding(.horizontal, 24)
    }
}

struct RoundEndView: View {
    let session: GameSession
    let round: Int
    let winners: [Int]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🏆")
                .font(.system(size: 64))
            Text("\(session.names(winners)) \(winners.count == 1 ? "wins" : "win") round \(round)!")
                .font(Theme.display(30))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            RoundStandingsView(session: session)
            Text("Next round starting soon…")
                .font(Theme.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct GameEndView: View {
    let session: GameSession
    let winner: Int
    var onClose: () -> Void
    var onHostRematch: (() -> Void)?
    var onJoinRematch: ((RematchInvite) -> Void)?

    @State private var rematchStarted = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🎉")
                .font(.system(size: 72))
            Text("\(session.name(winner)) wins the game!")
                .font(Theme.display(34))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            RoundStandingsView(session: session)
            VStack(spacing: 12) {
                if let onHostRematch {
                    Button {
                        rematchStarted = true
                        onHostRematch()
                        Task {
                            // If announcing failed (offline blip), come back
                            // to life so it can be tried again.
                            try? await Task.sleep(for: .seconds(6))
                            rematchStarted = false
                        }
                    } label: {
                        Label("Rematch — same crew", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(rematchStarted)
                } else if let invite = session.pendingRematch {
                    Text("🔁 \(session.name(1)) wants a rematch!")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.magenta)
                    Button {
                        onJoinRematch?(invite)
                    } label: {
                        Label("Join the rematch", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.magenta))
                } else {
                    Text("If \(session.name(1)) starts a rematch, you'll get a join request right here — no new link needed.")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                Button {
                    onClose()
                } label: {
                    Text("Back to home")
                        .frame(maxWidth: 240)
                }
                .buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 8)
            Spacer()
        }
    }
}

/// Shown once to a player who has just joined via an invite link, as soon
/// as the game details have been fetched and decrypted.
struct WelcomeView: View {
    let session: GameSession
    var onBegin: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: 140)
                .shadow(color: Theme.magenta.opacity(0.25), radius: 24)
            if let config = session.config {
                Text("Welcome \(config.name(session.mySlot))")
                    .font(Theme.display(34))
                    .multilineTextAlignment(.center)
                Text("to \(config.name(1))'s game!")
                    .font(Theme.title)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("First to \(config.roundsToWin) rounds wins. Head to the lobby while everyone joins.")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    onBegin()
                } label: {
                    Text("Begin")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 8)
            } else {
                ProgressView()
                Text("Getting your game ready…")
                    .font(Theme.headline)
                Text("Fetching and decrypting the game details.")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}
