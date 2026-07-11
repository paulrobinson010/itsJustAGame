import Foundation

/// Invite links look like:
///
///     itsjustagame://join/<gameID>/<slot>#<key>
///
/// The encryption key rides in the URL fragment. For the custom scheme this
/// is cosmetic (the URL never touches a server), but it means the format is
/// already correct if we later move to https universal links, where
/// fragments are not sent to the web server.
enum InviteLink {
    static let scheme = "itsjustagame"

    struct Parsed: Hashable {
        var gameID: String
        var slot: Int
        var keyBase64URL: String
    }

    static func url(gameID: String, slot: Int, key: String) -> String {
        "\(scheme)://join/\(gameID)/\(slot)#\(key)"
    }

    static func parse(_ url: URL) -> Parsed? {
        guard url.scheme?.lowercased() == scheme,
              url.host()?.lowercased() == "join" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2,
              let slot = Int(parts[1]),
              let key = url.fragment(), !key.isEmpty else { return nil }
        return Parsed(gameID: parts[0], slot: slot, keyBase64URL: key)
    }

    /// Tolerates surrounding text (e.g. a whole pasted message) by scanning
    /// for the first token that parses as an invite link.
    static func parse(text: String) -> Parsed? {
        for token in text.split(whereSeparator: \.isWhitespace) {
            if let url = URL(string: String(token)), let parsed = parse(url) {
                return parsed
            }
        }
        return nil
    }
}
