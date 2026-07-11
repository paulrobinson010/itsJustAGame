import Foundation

/// Invite links come in two equivalent forms, both carrying the encryption
/// key in the URL fragment — which browsers never send to any server:
///
///     itsjustagame://join/<gameID>/<slot>#<key>
///     https://itsjustagame.robbo-online.uk/join/<gameID>/<slot>#<key>
///
/// The app parses both. Which form gets *generated* is controlled by
/// `useUniversalLinks` — flip it to true once the domain and its GitHub
/// Pages site (in /docs) are live, and shared links become tappable
/// universal links that open the app directly.
enum InviteLink {
    static let scheme = "itsjustagame"
    static let webHost = "itsjustagame.robbo-online.uk"
    /// Keep false until the domain is serving /docs over HTTPS.
    static let useUniversalLinks = true

    struct Parsed: Hashable {
        var gameID: String
        var slot: Int
        var keyBase64URL: String
    }

    static func url(gameID: String, slot: Int, key: String) -> String {
        if useUniversalLinks {
            return "https://\(webHost)/join/\(gameID)/\(slot)#\(key)"
        }
        return "\(scheme)://join/\(gameID)/\(slot)#\(key)"
    }

    static func parse(_ url: URL) -> Parsed? {
        var parts = url.pathComponents.filter { $0 != "/" }
        if url.scheme?.lowercased() == scheme {
            guard url.host()?.lowercased() == "join" else { return nil }
        } else if url.scheme?.lowercased() == "https" || url.scheme?.lowercased() == "http" {
            guard url.host()?.lowercased() == webHost, parts.first == "join" else { return nil }
            parts.removeFirst()
        } else {
            return nil
        }
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
