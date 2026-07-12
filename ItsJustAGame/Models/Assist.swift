import Foundation

/// Per-player simplification, switched on by the host when the game is
/// created. Every mini game reads the player's level and quietly softens
/// itself — from gentle hints up to outright cheating. Nothing in play
/// tells the other players it's on.
enum AssistLevel: Int, Codable, CaseIterable, Hashable, Comparable {
    case little = 1
    case big = 2
    case cheating = 3

    var displayName: String {
        switch self {
        case .little: return "A little help"
        case .big: return "A big help"
        case .cheating: return "Basically cheating"
        }
    }

    static func < (lhs: AssistLevel, rhs: AssistLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
