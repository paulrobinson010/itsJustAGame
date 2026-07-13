import Foundation

/// In-memory mailbox for practice games: the host loop and the session on
/// this one device talk through a dictionary — no network, no iCloud,
/// nothing leaves the phone. Vanishes when the game screen closes.
final class LoopbackTransport: GameTransport, @unchecked Sendable {
    let tag = String(UUID().uuidString.prefix(4)).lowercased()
    private var records: [String: Data] = [:]
    private let lock = NSLock()

    func put(id: String, body: Data) async throws {
        lock.lock()
        defer { lock.unlock() }
        // Create-if-absent, same contract as CloudKit.
        if records[id] == nil {
            records[id] = body
        }
    }

    func get(ids: [String]) async throws -> [String: Data] {
        lock.lock()
        defer { lock.unlock() }
        var found: [String: Data] = [:]
        for id in ids {
            if let body = records[id] {
                found[id] = body
            }
        }
        return found
    }
}
