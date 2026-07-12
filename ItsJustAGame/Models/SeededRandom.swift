import Foundation

/// Deterministic RNG (SplitMix64). The host sends one seed in the turn
/// message and every device regenerates the identical layout from it —
/// tiny payloads, same picture everywhere.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum SharedLayout {
    struct Dot {
        let x: Double
        let y: Double
        let radius: Double
        let tint: Int
    }

    /// Scatter for Eyeball It, in unit-square coordinates.
    static func dots(seed: UInt64, count: Int) -> [Dot] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            Dot(
                x: Double.random(in: 0.05...0.95, using: &generator),
                y: Double.random(in: 0.05...0.95, using: &generator),
                radius: Double.random(in: 0.010...0.018, using: &generator),
                tint: Int.random(in: 0...2, using: &generator)
            )
        }
    }

    /// Non-overlapping tile spots for Sort Circuit, in unit-square
    /// coordinates. Rejection sampling with a deterministically relaxing
    /// minimum distance so it always terminates — identically everywhere.
    static func tilePositions(seed: UInt64, count: Int) -> [(x: Double, y: Double)] {
        var generator = SeededGenerator(seed: seed)
        var positions: [(x: Double, y: Double)] = []
        var attempts = 0
        while positions.count < count {
            attempts += 1
            let spacing = 0.24 * pow(0.98, Double(attempts / 40))
            let candidate = (
                x: Double.random(in: 0.12...0.88, using: &generator),
                y: Double.random(in: 0.12...0.88, using: &generator)
            )
            let clear = positions.allSatisfy {
                let dx = $0.x - candidate.x
                let dy = $0.y - candidate.y
                return (dx * dx + dy * dy).squareRoot() > spacing
            }
            if clear {
                positions.append(candidate)
            }
        }
        return positions
    }
}
