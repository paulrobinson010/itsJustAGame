import SwiftUI

/// One Shake It Off turn: shake the phone as hard as you can for the
/// window. A shake counts when user acceleration crosses the threshold
/// (with hysteresis so one wild swing isn't ten shakes). Counted locally,
/// so latency never matters.
struct ShakeTurnView: View {
    let session: GameSession
    let turn: ShakeTurn

    @State private var submitted = false
    @State private var shakes = 0
    /// Hysteresis: armed until a crossing, re-arms once things calm down.
    @State private var armed = true
    @State private var pulse = false

    private var motion: MotionService { MotionService.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let now = context.date
            let live = isLive(now: now)
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · shake like mad")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now, live: live)
                Spacer()
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 110))
                    .foregroundStyle(live ? Theme.cyan : Color.secondary)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(.easeOut(duration: 0.1), value: pulse)
                Spacer()
                Text("\(shakes)")
                    .font(Theme.display(56)).monospacedDigit()
                    .foregroundStyle(Theme.cyan)
                    .contentTransition(.numericText())
                Text("shakes").font(Theme.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .onChange(of: context.date) { _, _ in
                tick(now: Date())
            }
        }
        .task {
            submitted = session.hasSubmittedShake(for: turn)
            motion.start()
            if submitted { return }
            await autoFinish()
        }
        .onDisappear { motion.stop() }
    }

    @ViewBuilder
    private func header(now: Date, live: Bool) -> some View {
        if submitted {
            Text("\(shakes) shakes — waiting…").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else if now < turn.startAt {
            Text("Grip it tight…").font(Theme.display(24))
        } else if live {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("SHAKE! · \(remaining)s").font(Theme.display(28)).foregroundStyle(Theme.cyan)
        } else {
            Text("Time! — waiting…").font(Theme.headline)
        }
    }

    private func isLive(now: Date) -> Bool {
        !submitted && now >= turn.startAt && now < turn.deadline
    }

    private func tick(now: Date) {
        guard isLive(now: now) else { return }
        let g = motion.shakeG
        if armed && g >= threshold {
            armed = false
            shakes += 1
            pulse = true
            Task { try? await Task.sleep(for: .milliseconds(90)); pulse = false }
        } else if !armed && g < threshold * 0.45 {
            armed = true
        }
    }

    private func autoFinish() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitShake(shakes: shakes, for: turn)
    }

    // MARK: - Simplify

    /// A lower bar per shake — gentler wobbles count. Invisible to others.
    private var threshold: Double {
        switch session.myAssist {
        case .little: return GameTiming.shakeThresholdG * 0.75
        case .big: return GameTiming.shakeThresholdG * 0.55
        case .cheating: return GameTiming.shakeThresholdG * 0.4
        default: return GameTiming.shakeThresholdG
        }
    }
}

/// Most shakes takes the point.
struct ShakeRevealView: View {
    let session: GameSession
    let reveal: ShakeReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody shook a thing…"
                : "📳 \(session.names(reveal.winners)) shook the hardest!",
            rows: reveal.results
                .sorted { ($0.shakes ?? -1) > ($1.shakes ?? -1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "📳",
                              value: r.shakes.map { "\($0) shakes" }, empty: "sat it out")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next shake"
        )
    }
}
