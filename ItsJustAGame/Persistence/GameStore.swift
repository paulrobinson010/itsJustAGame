import Foundation
import Observation

/// Local persistence for the games this device is part of, including their
/// encryption keys. Written with complete file protection so keys are
/// encrypted at rest by iOS.
@MainActor
@Observable
final class GameStore {
    private(set) var games: [SavedGame] = []

    init() {
        load()
    }

    func add(_ game: SavedGame) {
        // Practice never persists — no code path should store one, but
        // guarantee it here regardless.
        guard game.practiceGame == nil else { return }
        games.removeAll { $0.gameID == game.gameID }
        games.insert(game, at: 0)
        save()
    }

    func remove(_ game: SavedGame) {
        games.removeAll { $0.gameID == game.gameID }
        save()
    }

    /// Rematch invite IDs the user has dismissed, so a discovered rematch
    /// they deleted isn't re-added the next time the app looks for invites.
    private let dismissedKey = "dismissedRematchIDs"
    var dismissedRematchIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dismissedKey) ?? [])
    }

    /// Delete a waiting rematch request and remember it, so it stays gone.
    func dismissRematch(_ game: SavedGame) {
        var dismissed = dismissedRematchIDs
        dismissed.insert(game.gameID)
        UserDefaults.standard.set(Array(dismissed), forKey: dismissedKey)
        remove(game)
    }

    func markWelcomed(_ game: SavedGame) {
        guard let index = games.firstIndex(where: { $0.gameID == game.gameID }) else { return }
        games[index].needsWelcome = false
        save()
    }

    func clearRematchPending(_ game: SavedGame) {
        guard let index = games.firstIndex(where: { $0.gameID == game.gameID }) else { return }
        games[index].rematchPending = nil
        save()
    }

    func recordSummary(_ summary: GameSummary, for game: SavedGame) {
        guard let index = games.firstIndex(where: { $0.gameID == game.gameID }),
              games[index].summary == nil else { return }
        games[index].summary = summary
        save()
    }

    private var fileURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("games.json")
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        games = (try? GameCrypto.decoder.decode([SavedGame].self, from: data)) ?? []
    }

    private func save() {
        guard let data = try? GameCrypto.encoder.encode(games) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
