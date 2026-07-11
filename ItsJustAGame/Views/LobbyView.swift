import SwiftUI

struct LobbyView: View {
    let session: GameSession
    let engine: HostEngine?
    let joined: Set<Int>
    @State private var composeTarget: ComposeTarget?

    private struct ComposeTarget: Identifiable {
        let slot: Int
        let phone: String
        let message: String
        var id: Int { slot }
    }

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
                            Circle()
                                .fill(player.color)
                                .frame(width: 10, height: 10)
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
                                if MessageComposeView.canSend,
                                   let phone = session.saved.inviteePhones?[player.slot] {
                                    Button {
                                        composeTarget = ComposeTarget(
                                            slot: player.slot,
                                            phone: phone,
                                            message: inviteMessage(for: player, config: config)
                                        )
                                    } label: {
                                        Image(systemName: "message.fill")
                                            .foregroundStyle(Theme.cyan)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                ShareLink(item: inviteMessage(for: player, config: config)) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderless)
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
                            .disabled(!engine.canBeginGame)
                        }
                    } footer: {
                        if joined.count < MiniGameType.smallestMinimum {
                            Text("At least \(MiniGameType.smallestMinimum) players must join before the game can start. Send each player their own link — the links carry the game's secret key, so share them privately.")
                        } else {
                            Text("Send each player their own link. The links carry the game's secret key, so everything stays end-to-end encrypted — share them privately.")
                        }
                    }
                } else {
                    Section {
                        Label("Waiting for \(session.name(1)) to start the game…", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .sheet(item: $composeTarget) { target in
            MessageComposeView(recipients: [target.phone], body: target.message)
        }
        .navigationTitle("Lobby")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The whole message is safe to paste into the app — the joiner just
    /// copies everything and the link is found inside it.
    private func inviteMessage(for player: PlayerInfo, config: GameConfig) -> String {
        let url = InviteLink.url(gameID: session.saved.gameID, slot: player.slot, key: session.saved.keyBase64URL)
        return "\(player.name), you're invited to \(config.name(1))'s game on It's Just a Game! Tap the link, or copy this whole message and paste it in the app:\n\(url)"
    }
}
