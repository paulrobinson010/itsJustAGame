import CryptoKit
import Foundation

/// Symmetric encryption for everything a game writes to the transport.
///
/// The 256-bit key is generated on the host device when the game is created
/// and travels only inside the invite links (in the URL fragment), so the
/// server (CloudKit) only ever stores ciphertext it cannot read. Anyone
/// holding an invite link holds the key — that's the trust model: the game
/// is private to the people who were sent a link.
struct GameCrypto {
    let key: SymmetricKey

    init() {
        self.key = SymmetricKey(size: .bits256)
    }

    init?(base64URL: String) {
        guard let data = Data(base64URL: base64URL), data.count == 32 else { return nil }
        self.key = SymmetricKey(data: data)
    }

    var base64URL: String {
        key.withUnsafeBytes { Data($0).base64URLEncodedString() }
    }

    func seal<T: Encodable>(_ value: T) throws -> Data {
        let plaintext = try Self.encoder.encode(value)
        return try ChaChaPoly.seal(plaintext, using: key).combined
    }

    func open<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let box = try ChaChaPoly.SealedBox(combined: data)
        let plaintext = try ChaChaPoly.open(box, using: key)
        return try Self.decoder.decode(type, from: plaintext)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }()
}

extension Data {
    init?(base64URL: String) {
        var base64 = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
