import SwiftUI

/// Full-screen container for an active game. Owns the session (every
/// device) and the host engine (host device only) and renders whichever
/// phase the game is in.
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
            Group {
                if showWelcome {
                    WelcomeView(session: session) {
                        showWelcome = false
                        model.store.markWelcomed(saved)
                    }
                } else {
                    phaseContent
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") { close() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let error = session.lastError ?? engine?.lastError {
                    Text(error)
                        .font(.caption)
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
        case .roundEnd(let round, let winner):
            RoundEndView(session: session, round: round, winner: winner)
        case .gameEnd(let winner):
            GameEndView(session: session, winner: winner) { close() }
        }
    }

    private func close() {
        model.activeGame = nil
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
            Text("👋")
                .font(.system(size: 64))
            if let config = session.config {
                Text("Welcome \(config.name(session.mySlot))")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("to \(config.name(1))'s game!")
                    .font(.title2)
                    .multilineTextAlignment(.center)
                Text("First to \(config.roundsToWin) rounds wins. Head to the lobby while everyone joins.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button {
                    onBegin()
                } label: {
                    Text("Begin")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            } else {
                ProgressView()
                Text("Getting your game ready…")
                    .font(.headline)
                Text("Fetching and decrypting the game details.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
    }
}

enum PlayerStyle {
    static let palette: [Color] = [.blue, .red, .green, .orange, .purple, .pink, .teal, .indigo]

    static func color(for slot: Int) -> Color {
        palette[(slot - 1 + palette.count * 8) % palette.count]
    }
}

struct ScoreBar: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 8) {
            ForEach(session.players) { player in
                VStack(spacing: 2) {
                    Text(player.name)
                        .font(.caption2)
                        .lineLimit(1)
                    Text("\(session.points[player.slot, default: 0])")
                        .font(.headline.monospacedDigit())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    PlayerStyle.color(for: player.slot).opacity(player.slot == session.mySlot ? 0.35 : 0.15),
                    in: Capsule()
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
        VStack(spacing: 16) {
            Spacer()
            Text("Round \(round)")
                .font(.title.bold())
            Image(systemName: "location.north.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
            Text(game.displayName)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("A place will appear. Point the arrow toward it — closest direction wins the point. First to \(GameTiming.pointsToWinRound) points takes the round.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Spacer()
        }
    }
}

struct RoundStandingsView: View {
    let session: GameSession

    var body: some View {
        VStack(spacing: 8) {
            ForEach(session.players) { player in
                HStack {
                    Circle()
                        .fill(PlayerStyle.color(for: player.slot))
                        .frame(width: 10, height: 10)
                    Text(player.name)
                        .lineLimit(1)
                    Spacer()
                    Text("\(session.roundsWon[player.slot, default: 0]) of \(session.config?.roundsToWin ?? 0) rounds")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 24)
    }
}

struct RoundEndView: View {
    let session: GameSession
    let round: Int
    let winner: Int

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🏆")
                .font(.system(size: 64))
            Text("\(session.name(winner)) wins round \(round)!")
                .font(.title.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            RoundStandingsView(session: session)
            Text("Next round starting soon…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }
}

struct GameEndView: View {
    let session: GameSession
    let winner: Int
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("🎉")
                .font(.system(size: 72))
            Text("\(session.name(winner)) wins the game!")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            RoundStandingsView(session: session)
            Button("Back to home") { onClose() }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
    }
}
