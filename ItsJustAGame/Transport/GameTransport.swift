import Foundation

/// A dumb, swappable mailbox. Bodies are always ciphertext — the transport
/// never sees game content, and record IDs are content-free (a random game
/// ID plus a structural suffix). Moving off CloudKit later (e.g. for
/// Android) only means re-implementing these two calls.
protocol GameTransport: Sendable {
    /// Create-if-absent. Publishing the same ID twice is a silent no-op.
    func put(id: String, body: Data) async throws

    /// Fetch whichever of the given IDs exist. Missing IDs are simply absent
    /// from the result.
    func get(ids: [String]) async throws -> [String: Data]

    /// Short identity beacon so diagnostics can prove two components hold
    /// the SAME transport instance (vital for in-memory transports).
    var tag: String { get }
}
