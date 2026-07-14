import Foundation
import Observation

/// The session and (for hosts) the engine, built together over ONE shared
/// transport. Owned by AppModel — never by a view — so presentation
/// lifecycle (spurious disappears, cover handoffs, state resets) can
/// neither kill the game loops nor split the pair.
struct GameStack {
    let saved: SavedGame
    let session: GameSession
    let engine: HostEngine?

    @MainActor
    init(saved: SavedGame) {
        self.saved = saved
        let crypto = GameCrypto(base64URL: saved.keyBase64URL) ?? GameCrypto()
        // Practice plays entirely on-device: the host loop and session
        // talk through an in-memory mailbox instead of CloudKit.
        let transport: any GameTransport = saved.practiceGame != nil
            ? LoopbackTransport()
            : CloudKitTransport()
        session = GameSession(saved: saved, transport: transport, crypto: crypto)
        if saved.isHost, let config = saved.hostConfig {
            engine = HostEngine(
                config: config,
                transport: transport,
                crypto: crypto,
                autoStart: saved.autoStart == true,
                practiceGame: saved.practiceGame
            )
        } else {
            engine = nil
        }
    }

    @MainActor
    func start() {
        session.start()
        engine?.start()
    }

    @MainActor
    func stop() {
        session.stop()
        engine?.stop()
    }
}

@MainActor
@Observable
final class AppModel {
    let store = GameStore()
    var activeGame: SavedGame? {
        didSet { syncStack() }
    }
    /// The live loops for the open game — created when a game opens,
    /// stopped and released when it closes or another game replaces it.
    private(set) var activeStack: GameStack?
    var joinError: String?

    /// The single place game loops are born and die. Keyed by gameID, so
    /// re-setting the same game (rerenders, bindings) is a no-op.
    private func syncStack() {
        if let game = activeGame {
            if activeStack?.saved.gameID != game.gameID {
                activeStack?.stop()
                activeStack = GameStack(saved: game)
                activeStack?.start()
            }
        } else {
            activeStack?.stop()
            activeStack = nil
        }
    }

    @discardableResult
    func createGame(
        roundsToWin: Int,
        playerNames: [String],
        inviteeAddresses: [Int: String] = [:],
        assists: [Int: AssistLevel] = [:]
    ) -> SavedGame {
        // Deal everyone a color at random from the palette, fixed for the
        // whole game.
        let colorIndices = Array(0..<PlayerStyle.palette.count).shuffled()
        let players = playerNames.enumerated().map { index, name in
            PlayerInfo(
                slot: index + 1,
                name: name,
                colorIndex: colorIndices[index % colorIndices.count],
                assist: assists[index + 1]
            )
        }
        let config = GameConfig(
            gameID: UUID().uuidString.lowercased(),
            roundsToWin: roundsToWin,
            players: players,
            createdAt: Date(),
            protocolVersion: AppProtocol.current
        )
        let crypto = GameCrypto()
        let saved = SavedGame(
            gameID: config.gameID,
            keyBase64URL: crypto.base64URL,
            mySlot: 1,
            isHost: true,
            hostConfig: config,
            title: "\(players.first?.name ?? "My")'s game · \(players.count) players",
            createdAt: Date(),
            inviteeAddresses: inviteeAddresses.isEmpty ? nil : inviteeAddresses
        )
        store.add(saved)
        activeGame = saved
        return saved
    }

    /// Solo practice: a one-player game over an in-memory transport that
    /// plays the chosen game round after round. Deliberately never stored —
    /// it leaves no trace in "Your games".
    func startPractice(_ game: MiniGameType, myName: String) {
        let name = myName.trimmingCharacters(in: .whitespaces)
        let config = GameConfig(
            gameID: "practice-" + UUID().uuidString.lowercased(),
            roundsToWin: 999,
            players: [PlayerInfo(
                slot: 1,
                name: name.isEmpty ? "You" : name,
                colorIndex: Int.random(in: 0..<PlayerStyle.palette.count)
            )],
            createdAt: Date(),
            protocolVersion: AppProtocol.current
        )
        let crypto = GameCrypto()
        activeGame = SavedGame(
            gameID: config.gameID,
            keyBase64URL: crypto.base64URL,
            mySlot: 1,
            isHost: true,
            hostConfig: config,
            title: "Practice — \(game.displayName)",
            createdAt: Date(),
            autoStart: true,
            practiceGame: game
        )
    }

    /// Take up a rematch invite: create (or reopen) the local SavedGame for
    /// the new game, keeping this device's slot and role from the old one.
    /// With `open` the game opens immediately (the player accepted, or the
    /// host started it); otherwise it waits as a request on the home screen.
    func adoptRematch(_ invite: RematchInvite, from old: SavedGame, open: Bool) {
        if let existing = store.games.first(where: { $0.gameID == invite.newGameID }) {
            if open {
                acceptRematch(existing)
            }
            return
        }
        let saved = SavedGame(
            gameID: invite.newGameID,
            keyBase64URL: invite.newKeyBase64URL,
            mySlot: old.isHost ? 1 : old.mySlot,
            isHost: old.isHost,
            hostConfig: old.isHost ? invite.config : nil,
            title: "\(invite.config.name(1))'s game · \(invite.config.players.count) players",
            createdAt: Date(),
            needsWelcome: false,
            inviteeAddresses: old.isHost ? old.inviteeAddresses : nil,
            autoStart: true,
            rematchPending: open ? nil : true
        )
        store.add(saved)
        if open { activeGame = saved }
    }

    /// The player tapped a rematch request — joining happens by opening
    /// the game (the session announces them to the host automatically).
    func acceptRematch(_ game: SavedGame) {
        store.clearRematchPending(game)
        activeGame = store.games.first { $0.gameID == game.gameID } ?? game
    }

    /// Rematch invites are parked at a well-known record ID on the old
    /// game, so a player who wasn't in the app when "Play again" was
    /// tapped still gets the request the moment they open it. Found ones
    /// appear as a "Rematch waiting" request on the home screen — never
    /// auto-joined.
    func discoverRematches() async {
        guard activeGame == nil else { return }
        let transport = CloudKitTransport()
        // Recent games regardless of stored summary — a device killed at
        // the final screen may never have recorded one. Unfinished games
        // simply have no rematch record to find.
        for old in store.games.prefix(5) {
            guard let crypto = GameCrypto(base64URL: old.keyBase64URL) else { continue }
            let id = RecordName.rematch(old.gameID)
            guard let found = try? await transport.get(ids: [id]),
                  let body = found[id],
                  let invite = try? crypto.open(RematchInvite.self, from: body),
                  !store.games.contains(where: { $0.gameID == invite.newGameID }) else { continue }
            adoptRematch(invite, from: old, open: false)
        }
    }

    func join(text: String) {
        guard let parsed = InviteLink.parse(text: text) else {
            joinError = "That doesn't look like a game link."
            return
        }
        join(parsed)
    }

    func handle(url: URL) {
        guard let parsed = InviteLink.parse(url) else { return }
        join(parsed)
    }

    private func join(_ parsed: InviteLink.Parsed) {
        guard GameCrypto(base64URL: parsed.keyBase64URL) != nil else {
            joinError = "The link is missing or has a broken encryption key."
            return
        }
        if let existing = store.games.first(where: { $0.gameID == parsed.gameID }) {
            if existing.isHost || existing.mySlot == parsed.slot {
                joinError = nil
                activeGame = existing
                return
            }
            // A different player's link for the same game: adopt the new
            // identity instead of silently rejoining as the old one.
            store.remove(existing)
        }
        let saved = SavedGame(
            gameID: parsed.gameID,
            keyBase64URL: parsed.keyBase64URL,
            mySlot: parsed.slot,
            isHost: false,
            hostConfig: nil,
            title: "Joined game",
            createdAt: Date(),
            needsWelcome: true
        )
        store.add(saved)
        joinError = nil
        activeGame = saved
    }
}
