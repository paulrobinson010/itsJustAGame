import SwiftUI

struct LobbyView: View {
    let session: GameSession
    let engine: HostEngine?
    let joined: Set<Int>

    var body: some View {
        List {
            if session.config == nil {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Fetching game details…")
                    }
                } footer: {
                    Text("Make sure you're online and signed in to iCloud.")
                }
            }

            if let config = session.config {
                Section("Players — first to \(config.roundsToWin) rounds wins") {
                    ForEach(config.players) { player in
                        HStack {
                            Image(systemName: joined.contains(player.slot) ? "checkmark.circle.fill" : "circle.dotted")
                                .foregroundStyle(joined.contains(player.slot) ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.name)
                                if player.slot == session.mySlot {
                                    Text("You")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if session.saved.isHost && player.slot != 1 {
                                ShareLink(item: inviteURL(for: player)) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                    }
                }

                if session.saved.isHost, let engine {
                    Section {
                        if engine.resumeBlocked {
                            Text("This game already started on a previous launch. Resuming a game as the host isn't supported yet — please start a new game.")
                                .foregroundStyle(.orange)
                        } else {
                            Button {
                                engine.beginGame()
                            } label: {
                                Label(
                                    joined.count == config.players.count
                                        ? "Start game"
                                        : "Start with \(joined.count) of \(config.players.count) players",
                                    systemImage: "play.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(engine.gameRunning)
                        }
                    } footer: {
                        Text("Send each player their own link. The links carry the game's secret key, so everything stays end-to-end encrypted — share them privately.")
                    }
                } else {
                    Section {
                        Label("Waiting for \(session.name(1)) to start the game…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Lobby")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func inviteURL(for player: PlayerInfo) -> String {
        InviteLink.url(gameID: session.saved.gameID, slot: player.slot, key: session.saved.keyBase64URL)
    }
}
