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
        games.removeAll { $0.gameID == game.gameID }
        games.insert(game, at: 0)
        save()
    }

    func remove(_ game: SavedGame) {
        games.removeAll { $0.gameID == game.gameID }
        save()
    }

    func markWelcomed(_ game: SavedGame) {
        guard let index = games.firstIndex(where: { $0.gameID == game.gameID }) else { return }
        games[index].needsWelcome = false
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
