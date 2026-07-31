import Foundation

/// The nearby (no-internet) mailbox. Same two calls as CloudKit, but the
/// records live on the host phone and travel by MultipeerConnectivity:
/// the host reads and writes its own store directly; a peer's put/get is
/// a tiny request to the host. Bodies stay ciphertext throughout — this
/// transport is as content-blind as the others.
final class MultipeerTransport: GameTransport, @unchecked Sendable {
    private let service: NearbyService
    private let isHost: Bool

    init(service: NearbyService, isHost: Bool) {
        self.service = service
        self.isHost = isHost
    }

    func put(id: String, body: Data) async throws {
        if isHost {
            service.storeLocal(id: id, body: body)
        } else {
            service.sendPut(id: id, body: body)
        }
    }

    func get(ids: [String]) async throws -> [String: Data] {
        if isHost {
            return service.fetchLocal(ids: ids)
        } else {
            return await service.requestRecords(ids: ids)
        }
    }
}
