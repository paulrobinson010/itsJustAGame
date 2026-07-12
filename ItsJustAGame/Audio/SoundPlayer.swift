import AVFoundation
import Foundation

/// Central sound effects. All effects are tiny bundled WAVs, synthesized
/// in an arcade flavor to match the neon look. No in-app mute: the audio
/// session is ambient, so the ring/silent switch and the volume buttons
/// are the controls — and it mixes with the user's music.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    enum Effect: String, CaseIterable {
        case tick        // wheel clicks, pad taps, sequence flashes
        case lockin      // answer confirmed
        case point       // turn/match won
        case lose        // eliminated / nobody scored / false start
        case zap         // lightning flash
        case roundwin    // round won
        case fanfare     // game won / tie-break resolved
        case drumroll    // loops during the tie-break spin
    }

    private var players: [Effect: AVAudioPlayer] = [:]
    /// Ticks overlap at high spin speed — rotate through a small pool.
    private var tickPool: [AVAudioPlayer] = []
    private var tickIndex = 0

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { continue }
            if effect == .tick {
                tickPool = (0..<4).compactMap { _ in try? AVAudioPlayer(contentsOf: url) }
                for player in tickPool {
                    player.volume = 0.5
                    player.prepareToPlay()
                }
            } else if let player = try? AVAudioPlayer(contentsOf: url) {
                player.volume = volume(for: effect)
                player.prepareToPlay()
                players[effect] = player
            }
        }
        players[.drumroll]?.numberOfLoops = -1
    }

    private func volume(for effect: Effect) -> Float {
        switch effect {
        case .tick: return 0.5
        case .lockin: return 0.45
        case .point: return 0.7
        case .lose: return 0.5
        case .zap: return 0.8
        case .roundwin: return 0.8
        case .fanfare: return 0.9
        case .drumroll: return 0.45
        }
    }

    func play(_ effect: Effect) {
        if effect == .tick {
            guard !tickPool.isEmpty else { return }
            let player = tickPool[tickIndex % tickPool.count]
            tickIndex += 1
            player.currentTime = 0
            player.play()
            return
        }
        guard let player = players[effect] else { return }
        player.currentTime = 0
        player.play()
    }

    func startDrumroll() {
        players[.drumroll]?.currentTime = 0
        players[.drumroll]?.play()
    }

    func stopDrumroll() {
        players[.drumroll]?.stop()
    }
}
