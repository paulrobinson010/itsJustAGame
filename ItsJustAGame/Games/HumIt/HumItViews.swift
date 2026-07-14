import AVFoundation
import SwiftUI

/// One Hum It turn: the reference note plays, then you hum it back. The
/// device tracks your pitch and reports the error in cents; closest wins.
struct HumTurnView: View {
    let session: GameSession
    let turn: HumTurn

    @State private var submitted = false
    @State private var micDenied = false
    @State private var samples: [Double] = []
    @State private var player: AVAudioPlayer?

    private var mic: MicService { MicService.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            let humming = now >= turn.humStart && now < turn.deadline && !submitted
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · match the note")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.4)
                header(now: now, humming: humming)
                Spacer()
                Image(systemName: humming ? "waveform" : "music.note")
                    .font(.system(size: 80))
                    .foregroundStyle(humming ? Theme.cyan : .secondary)
                    .symbolEffect(.pulse, isActive: humming)
                if humming { feedback }
                Spacer()
            }
            .padding(.top, 8)
            .onChange(of: context.date) { _, _ in
                if humming {
                    let p = mic.pitchHz
                    if p > 70, p < 600 { samples.append(p) }
                }
            }
        }
        .task {
            submitted = session.hasSubmittedHum(for: turn)
            if submitted { return }
            let ok = await mic.start()
            micDenied = !ok
            await sequence()
        }
        .onDisappear { mic.stop(); player?.stop() }
    }

    @ViewBuilder
    private func header(now: Date, humming: Bool) -> some View {
        if submitted {
            Text("Lovely — waiting…").font(Theme.display(24))
        } else if micDenied {
            Text("Microphone needed for this one")
                .font(Theme.subheadline).foregroundStyle(Theme.magenta)
        } else if now < turn.humStart {
            Text("Listen… 🎵").font(Theme.display(28)).foregroundStyle(Theme.magenta)
        } else if humming {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("Now hum it! · \(remaining)s").font(Theme.display(26)).foregroundStyle(Theme.cyan)
        } else {
            Text("Time's up — waiting…").font(Theme.headline)
        }
    }

    /// Simplify feedback while humming: an up/down arrow (level 1), and a
    /// live cents readout (levels 2–3).
    @ViewBuilder
    private var feedback: some View {
        let current = mic.pitchHz
        if current > 70, let level = session.myAssist {
            let cents = 1200 * log2(current / turn.targetHz)
            switch level {
            case .little:
                Text(abs(cents) < 30 ? "🎯 spot on!" : (cents > 0 ? "⬇︎ a bit lower" : "⬆︎ a bit higher"))
                    .font(Theme.headline).foregroundStyle(Theme.cyan)
            case .big, .cheating:
                Text(String(format: "%+.0f cents", cents))
                    .font(Theme.subheadline.monospacedDigit()).foregroundStyle(Theme.cyan)
            }
        }
    }

    private func sequence() async {
        // Wait for the intro, then play the reference tone.
        let wait = turn.startAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
        playTone()
        // Auto-submit at the deadline.
        let untilEnd = turn.deadline.timeIntervalSinceNow
        if untilEnd > 0 { try? await Task.sleep(for: .seconds(untilEnd)) }
        guard !Task.isCancelled, !submitted else { return }
        submit()
    }

    private func playTone() {
        let seconds = session.myAssist == .little ? turn.listenSeconds * 1.6 : turn.listenSeconds
        let data = ToneWAV.data(frequency: turn.targetHz, seconds: seconds)
        player = try? AVAudioPlayer(data: data)
        player?.play()
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        // Median of the sustained hum pitch → error in cents.
        let errorCents: Int
        if samples.count >= 3 {
            let sorted = samples.sorted()
            let median = sorted[sorted.count / 2]
            errorCents = Int(abs(1200 * log2(median / turn.targetHz)).rounded())
        } else {
            errorCents = 9999  // never really hummed
        }
        SoundPlayer.shared.play(.lockin)
        session.submitHum(errorCents: errorCents, for: turn)
    }
}

struct HumRevealView: View {
    let session: GameSession
    let reveal: HumReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty ? "Nobody found the note…" : "🎵 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!",
            rows: reveal.results
                .sorted { ($0.errorCents ?? .max) < ($1.errorCents ?? .max) }
                .map { r in
                    let text: String? = {
                        guard let c = r.errorCents, c < 9999 else { return nil }
                        return "\(c)¢ off"
                    }()
                    return SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🎵",
                                     value: text, empty: "no hum")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next note"
        )
    }
}
