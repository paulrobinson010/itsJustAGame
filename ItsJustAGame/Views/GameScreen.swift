import SwiftUI

/// Full-screen container for an active game. Owns the session (every
/// device) and the host engine (host device only) and renders whichever
/// phase the game is in, cross-fading between phases.
struct GameScreen: View {
    let saved: SavedGame
    let model: AppModel
    @State private var session: GameSession
    @State private var engine: HostEngine?
    @State private var showWelcome: Bool

    init(saved: SavedGame, model: AppModel) {
        self.saved = saved
        self.model = model
        let crypto = GameCrypto(base64URL: saved.keyBase64URL) ?? GameCrypto()
        let transport = CloudKitTransport()
        _session = State(initialValue: GameSession(saved: saved, transport: transport, crypto: crypto))
        _showWelcome = State(initialValue: saved.needsWelcome == true)
        if saved.isHost, let config = saved.hostConfig {
            _engine = State(initialValue: HostEngine(config: config, transport: transport, crypto: crypto))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                content
                    .id(contentKey)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .animation(.easeInOut(duration: 0.35), value: contentKey)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") { close() }
                }
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
        .task {
            session.start()
            engine?.start()
        }
        .onDisappear {
            session.stop()
            engine?.stop()
        }
    }

    @ViewBuilder
    private var content: some View {
        if showWelcome {
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
        guard !showWelcome else { return "welcome" }
        switch session.phase {
        case .lobby: return "lobby"
        case .wheel(let round, _): return "wheel\(round)"
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
        case .wheel(let round, let chooser):
            WheelPhaseView(session: session, round: round, chooser: chooser)
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
        case .roundEnd(let round, let winners):
            RoundEndView(session: session, round: round, winners: winners)
        case .tieBreak(let candidates, let winner):
            TieBreakView(session: session, candidates: candidates, winner: winner)
        case .gameEnd(let winner):
            GameEndView(
                session: session,
                winner: winner,
                onClose: { close() },
                onHostRematch: saved.isHost ? { hostRematch() } : nil,
                onJoinRematch: { invite in joinRematch(invite) }
            )
        }
    }

    private func close() {
        model.activeGame = nil
    }

    private func hostRematch() {
        guard let engine else { return }
        Task {
            guard var newSaved = await engine.announceRematch() else { return }
            newSaved.inviteeAddresses = saved.inviteeAddresses
            model.store.add(newSaved)
            model.activeGame = newSaved
        }
    }

    private func joinRematch(_ invite: RematchInvite) {
        if let existing = model.store.games.first(where: { $0.gameID == invite.newGameID }) {
            model.activeGame = existing
            return
        }
        let newSaved = SavedGame(
            gameID: invite.newGameID,
            keyBase64URL: invite.newKeyBase64URL,
            mySlot: session.mySlot,
            isHost: false,
            hostConfig: nil,
            title: "\(invite.config.name(1))'s game · \(invite.config.players.count) players",
            createdAt: Date(),
            needsWelcome: false
        )
        model.store.add(newSaved)
        model.activeGame = newSaved
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
                .font(Theme.subheadline)
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
                    } label: {
                        Label("Rematch — same crew", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(rematchStarted)
                } else if let invite = session.pendingRematch, let onJoinRematch {
                    Button {
                        onJoinRematch(invite)
                    } label: {
                        Label("Join the rematch", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: 240)
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.magenta))
                } else {
                    Text("If \(session.name(1)) starts a rematch, you can join it from here — no new link needed.")
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
