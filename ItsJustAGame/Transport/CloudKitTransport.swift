import CloudKit
import Foundation

/// CloudKit-backed mailbox using the public database.
///
/// Everything is fetched by record ID, never by query, so no custom indexes
/// are needed: the "GameMessage" record type is created just-in-time on
/// first save in the development environment. The public database is fine
/// because every body is ciphertext — CloudKit is storage, not a trust
/// boundary.
final class CloudKitTransport: GameTransport, @unchecked Sendable {
    static let recordType = "GameMessage"
    let tag = "ck"

    private let database: CKDatabase

    init(container: CKContainer = .default()) {
        self.database = container.publicCloudDatabase
    }

    func put(id: String, body: Data) async throws {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: id))
        record["body"] = body as NSData
        do {
            _ = try await database.save(record)
        } catch let error as CKError where error.code == .serverRecordChanged {
            // The record already exists — puts are idempotent by design.
        }
    }

    func get(ids: [String]) async throws -> [String: Data] {
        guard !ids.isEmpty else { return [:] }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0) }
        let results = try await database.records(for: recordIDs)
        var found: [String: Data] = [:]
        for (recordID, result) in results {
            if case .success(let record) = result, let body = record["body"] as? Data {
                found[recordID.recordName] = body
            }
        }
        return found
    }

    static func accountStatus() async -> CKAccountStatus {
        (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine
    }
}
