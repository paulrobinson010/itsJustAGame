import SwiftUI
import UIKit

/// One Feel the Beat turn: a rhythm buzzes through the phone (haptic + a
/// soft tick), then you tap it straight back. The device compares your
/// tap gaps to the pattern and reports the average error in ms; closest
/// wins. Nothing but a number leaves the phone.
struct BeatTurnView: View {
    let session: GameSession
    let turn: BeatTurn

    @State private var submitted = false
    @State private var canTap = false
    @State private var taps: [Date] = []
    @State private var pulse = false

    /// Beats in the pattern (one more than the number of gaps).
    private var beatsNeeded: Int { turn.gaps.count + 1 }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · feel the beat")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.3)
                header(now: now)
                Spacer()
                pad
                Spacer()
                progress
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedBeat(for: turn)
            if submitted { return }
            await run()
        }
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        if submitted {
            Text("Nice rhythm — waiting…").font(Theme.display(22))
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if !canTap {
            Text("Feel it… 🥁").font(Theme.display(26)).foregroundStyle(Theme.magenta)
        } else {
            Text("Now tap it back!").font(Theme.display(24)).foregroundStyle(Theme.cyan)
        }
    }

    private var pad: some View {
        ZStack {
            Circle()
                .fill(canTap ? Theme.cyan.opacity(0.18) : Theme.surface)
                .overlay(Circle().stroke(pulse ? Theme.magenta : Theme.hairline, lineWidth: pulse ? 5 : 1))
                .frame(width: 200, height: 200)
                .scaleEffect(pulse ? 1.08 : 1.0)
                .animation(.easeOut(duration: 0.12), value: pulse)
            Image(systemName: canTap ? "hand.tap.fill" : "waveform.path")
                .font(.system(size: 64))
                .foregroundStyle(canTap ? Theme.cyan : .secondary)
        }
        .contentShape(Circle())
        .onTapGesture { registerTap() }
        .allowsHitTesting(canTap && !submitted)
    }

    private var progress: some View {
        HStack(spacing: 10) {
            ForEach(0..<beatsNeeded, id: \.self) { i in
                Circle()
                    .fill(i < taps.count ? Theme.cyan : Theme.surface)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    .frame(width: 14, height: 14)
            }
        }
    }

    // MARK: - Playback + tapping

    private func run() async {
        let wait = turn.startAt.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }

        // Simplify (little+) plays the pattern through twice.
        let replays = session.myAssist == nil ? 1 : 2
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        for play in 0..<replays {
            await playPattern(generator)
            if play < replays - 1 { try? await Task.sleep(for: .milliseconds(700)) }
        }

        canTap = true
        // Cheating: a visual metronome keeps looping so you can tap along.
        if session.myAssist == .cheating {
            Task { await tapAlongLoop() }
        }

        let untilEnd = turn.deadline.timeIntervalSinceNow
        if untilEnd > 0 { try? await Task.sleep(for: .seconds(untilEnd)) }
        submit()
    }

    private func playPattern(_ generator: UIImpactFeedbackGenerator) async {
        beat(generator, visible: showsFlash)
        for gap in turn.gaps {
            try? await Task.sleep(for: .milliseconds(gap))
            beat(generator, visible: showsFlash)
        }
    }

    private func tapAlongLoop() async {
        while canTap && !submitted && !Task.isCancelled && Date() < turn.deadline {
            beat(nil, visible: true)
            for gap in turn.gaps {
                try? await Task.sleep(for: .milliseconds(gap))
                if !canTap || submitted || Date() >= turn.deadline { return }
                beat(nil, visible: true)
            }
            try? await Task.sleep(for: .milliseconds(900))
        }
    }

    /// One beat: haptic + soft tick, and a visual pulse when help is on.
    private func beat(_ generator: UIImpactFeedbackGenerator?, visible: Bool) {
        generator?.impactOccurred()
        SoundPlayer.shared.play(.tick)
        if visible { flash() }
    }

    private func flash() {
        pulse = true
        Task {
            try? await Task.sleep(for: .milliseconds(110))
            pulse = false
        }
    }

    private func registerTap() {
        guard canTap, !submitted else { return }
        taps.append(Date())
        SoundPlayer.shared.play(.tick)
        flash()
        if taps.count >= beatsNeeded { submit() }
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        let errorMs: Int
        let measured = min(turn.gaps.count, max(0, taps.count - 1))
        if measured >= 1 {
            var total = 0.0
            for i in 0..<measured {
                let gap = taps[i + 1].timeIntervalSince(taps[i]) * 1000
                total += abs(gap - Double(turn.gaps[i]))
            }
            let mean = total / Double(measured)
            // A penalty for any beats not tapped back at all.
            let missing = turn.gaps.count - measured
            errorMs = Int(mean.rounded()) + missing * 400
        } else {
            errorMs = 99999
        }
        SoundPlayer.shared.play(.lockin)
        session.submitBeat(errorMs: errorMs, for: turn)
    }

    // MARK: - Simplify

    /// A visual pulse accompanies the haptic during playback (levels 2–3).
    private var showsFlash: Bool {
        guard let level = session.myAssist else { return false }
        return level >= .big
    }
}

/// Closest to the rhythm takes the point.
struct BeatRevealView: View {
    let session: GameSession
    let reveal: BeatReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody found the beat…"
                : "🥁 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!",
            rows: reveal.results
                .sorted { ($0.errorMs ?? .max) < ($1.errorMs ?? .max) }
                .map { r in
                    let text: String? = {
                        guard let e = r.errorMs, e < 99999 else { return nil }
                        return "\(e)ms off"
                    }()
                    return SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🥁",
                                     value: text, empty: "no taps")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next beat"
        )
    }
}
