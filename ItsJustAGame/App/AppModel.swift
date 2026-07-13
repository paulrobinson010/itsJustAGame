import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let store = GameStore()
    var activeGame: SavedGame?
    var joinError: String?

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
            createdAt: Date()
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

    /// Take up a rematch invite: create (or reopen) the local SavedGame for
    /// the new game, keeping this device's slot and role from the old one.
    func adoptRematch(_ invite: RematchInvite, from old: SavedGame, open: Bool) {
        if let existing = store.games.first(where: { $0.gameID == invite.newGameID }) {
            if open { activeGame = existing }
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
            autoStart: true
        )
        store.add(saved)
        if open { activeGame = saved }
    }

    /// Rematch invites are parked at a well-known record ID on the old
    /// game, so a player who wasn't in the app when "Play again" was
    /// tapped still finds the new game the moment they open it. Jumps
    /// straight into the freshest one found.
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
            adoptRematch(invite, from: old, open: activeGame == nil)
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
