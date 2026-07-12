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
