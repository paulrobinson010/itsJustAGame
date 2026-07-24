import SwiftUI

struct LobbyView: View {
    let session: GameSession
    let engine: HostEngine?
    let joined: Set<Int>
    @State private var composeTarget: ComposeTarget?
    @State private var inviteQueue: [ComposeTarget] = []

    private struct ComposeTarget: Identifiable {
        let slot: Int
        let address: String
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
                            Text(player.name)
                            if player.slot == session.mySlot {
                                Text("· you")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(joined.contains(player.slot) ? "In!" : "waiting")
                                .font(Theme.caption)
                                .foregroundStyle(joined.contains(player.slot) ? .green : .secondary)
                        }
                    }
                }

                if session.saved.isHost, let engine {
                    let waiting = waitingPlayers(config: config)
                    if !waiting.isEmpty && session.saved.autoStart != true && session.saved.practiceGame == nil {
                        Section {
                            ForEach(waiting) { player in
                                inviteRow(for: player, config: config)
                            }
                            let pending = pendingInvitees(config: config)
                            if pending.count > 1 {
                                Button {
                                    startInviteAll(pending)
                                } label: {
                                    Label("Invite all by iMessage (\(pending.count))", systemImage: "paperplane.fill")
                                }
                            }
                        } header: {
                            Text("Send the invites")
                        } footer: {
                            Text("Each player gets their own link — it carries the game's secret key, so send it privately. Share works with any app: iMessage, WhatsApp, email…")
                        }
                    }

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
                                .font(Theme.headline)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.cyan)
                            .disabled(!engine.canBeginGame)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    } footer: {
                        if session.saved.practiceGame != nil {
                            Text("Practice — starting…")
                        } else if session.saved.autoStart == true {
                            Text("It's a rematch — no new links needed. The others get a join request in their app, and the game starts by itself when everyone's in.")
                        } else if joined.count < MiniGameType.smallestMinimum {
                            Text("The game can start once \(MiniGameType.smallestMinimum) players are in.")
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
        .sheet(item: $composeTarget, onDismiss: advanceInviteQueue) { target in
            MessageComposeView(recipients: [target.address], body: target.message)
        }
        .navigationTitle("Lobby")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One clear row per player yet to join: their name plus big, labelled
    /// invite buttons — no tiny icons to hunt for.
    private func inviteRow(for player: PlayerInfo, config: GameConfig) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(player.name)
                .font(Theme.headline)
            HStack(spacing: 10) {
                if MessageComposeView.canSend,
                   let address = session.saved.inviteeAddresses?[player.slot] {
                    Button {
                        composeTarget = ComposeTarget(
                            slot: player.slot,
                            address: address,
                            message: inviteMessage(for: player, config: config)
                        )
                    } label: {
                        Label("iMessage", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.cyan)
                }
                ShareLink(item: inviteMessage(for: player, config: config)) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }

    /// Players (other than the host) who haven't joined yet.
    private func waitingPlayers(config: GameConfig) -> [PlayerInfo] {
        config.players.filter { $0.slot != 1 && !joined.contains($0.slot) }
    }

    /// Everyone picked from contacts who hasn't joined yet.
    private func pendingInvitees(config: GameConfig) -> [ComposeTarget] {
        guard MessageComposeView.canSend else { return [] }
        return config.players.compactMap { player in
            guard player.slot != 1,
                  !joined.contains(player.slot),
                  let address = session.saved.inviteeAddresses?[player.slot] else { return nil }
            return ComposeTarget(
                slot: player.slot,
                address: address,
                message: inviteMessage(for: player, config: config)
            )
        }
    }

    /// Walk the composers back-to-back: each dismissal presents the next.
    private func startInviteAll(_ targets: [ComposeTarget]) {
        guard let first = targets.first else { return }
        inviteQueue = Array(targets.dropFirst())
        composeTarget = first
    }

    private func advanceInviteQueue() {
        guard !inviteQueue.isEmpty else { return }
        let next = inviteQueue.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            composeTarget = next
        }
    }

    /// The whole message is safe to paste into the app — the joiner just
    /// copies everything and the link is found inside it.
    private func inviteMessage(for player: PlayerInfo, config: GameConfig) -> String {
        let url = InviteLink.url(gameID: session.saved.gameID, slot: player.slot, key: session.saved.keyBase64URL)
        return "\(player.name), you're invited to \(config.name(1))'s game on It's Just a Game! Tap the link, or copy this whole message and paste it in the app:\n\(url)"
    }
}
