import SwiftUI

/// The rope's sway: where the balance point sits at any moment, built from
/// the seed so every device walks the identical rope. It sways gently at
/// first and swings wider the further you get.
struct RopeSway {
    private let f1: Double
    private let f2: Double
    private let p1: Double
    private let p2: Double
    private let maxSeconds: Double

    init(seed: UInt64, maxSeconds: Double) {
        var generator = SeededGenerator(seed: seed)
        f1 = Double.random(in: 1.4...2.2, using: &generator)   // rad/s
        f2 = Double.random(in: 3.2...4.6, using: &generator)
        p1 = Double.random(in: 0...(2 * .pi), using: &generator)
        p2 = Double.random(in: 0...(2 * .pi), using: &generator)
        self.maxSeconds = maxSeconds
    }

    /// Balance-point offset in degrees of roll at `t` seconds in.
    func center(at t: Double) -> Double {
        let amplitude = 2.0 + 8.0 * min(1, t / maxSeconds)
        return amplitude * (sin(f1 * t + p1) + 0.6 * sin(f2 * t + p2)) / 1.6
    }
}

/// One Tightrope turn: tilt to keep the walker over the swaying rope while
/// they stride forward — and hold the phone smoothly, because jolts narrow
/// your balance. Distance is measured locally; furthest wins, and a fall
/// freezes your distance where you dropped.
struct RopeTurnView: View {
    let session: GameSession
    let turn: RopeTurn

    @State private var submitted = false
    @State private var fell = false
    @State private var distance = 0.0        // metres
    @State private var offBalance = 0.0      // seconds out, decaying
    @State private var wobble = 0.0          // jolt accumulator 0…1
    @State private var lastTick: Date?

    private let sway: RopeSway

    init(session: GameSession, turn: RopeTurn) {
        self.session = session
        self.turn = turn
        self.sway = RopeSway(seed: turn.seed, maxSeconds: turn.maxSeconds)
    }

    private var motion: MotionService { MotionService.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let now = context.date
            let live = isLive(now: now)
            let roll = motion.rollDegrees
            let center = sway.center(at: max(0, now.timeIntervalSince(turn.startAt)))
            let inBalance = abs(roll - center) <= effectiveHalfWidth
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · stay on the rope")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now, live: live, inBalance: inBalance)
                Spacer(minLength: 8)
                gauge(roll: roll, center: center, inBalance: inBalance && live)
                walker(live: live, inBalance: inBalance)
                Spacer(minLength: 8)
                Text(String(format: "%.1f m", distance))
                    .font(Theme.display(44)).monospacedDigit()
                    .foregroundStyle(fell ? Theme.magenta : Theme.cyan)
                Text("along the rope").font(Theme.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .onChange(of: context.date) { _, newDate in
                advance(now: newDate)
            }
        }
        .task {
            submitted = session.hasSubmittedRope(for: turn)
            motion.start()
            if submitted { return }
            await autoFinish()
        }
        .onDisappear { motion.stop() }
    }

    @ViewBuilder
    private func header(now: Date, live: Bool, inBalance: Bool) -> some View {
        if fell {
            Text("Fell off! — waiting…").font(Theme.display(20)).foregroundStyle(Theme.magenta)
        } else if submitted {
            Text(String(format: "%.1f m — waiting…", distance)).font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else if now < turn.startAt {
            Text("On the rope…").font(Theme.display(24))
        } else if !live {
            Text("Time! — waiting…").font(Theme.headline)
        } else if inBalance {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("Steady on · \(remaining)s").font(Theme.display(24)).foregroundStyle(Theme.cyan)
        } else {
            Text("Wobbling! ⚠️").font(Theme.display(24)).foregroundStyle(.orange)
        }
    }

    /// The balance bar: the rope's sway point drifts, your bubble follows
    /// the roll. Stay inside the band.
    private func gauge(roll: Double, center: Double, inBalance: Bool) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let scale = width / 60          // ±30° of roll on screen
            let bandWidth = effectiveHalfWidth * 2 * scale
            ZStack {
                Capsule()
                    .fill(Theme.surface)
                    .frame(height: 18)
                Capsule()
                    .fill((inBalance ? Color.green : Theme.magenta).opacity(0.35))
                    .frame(width: bandWidth, height: 18)
                    .offset(x: center * scale)
                Circle()
                    .fill(inBalance ? Theme.cyan : Theme.magenta)
                    .frame(width: 26, height: 26)
                    .offset(x: min(width / 2, max(-width / 2, roll * scale)))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 44)
        .padding(.horizontal, 24)
    }

    private func walker(live: Bool, inBalance: Bool) -> some View {
        Image(systemName: fell ? "figure.fall" : "figure.walk")
            .font(.system(size: 80))
            .foregroundStyle(fell ? Theme.magenta : (live && inBalance ? Theme.cyan : Color.secondary))
            .rotationEffect(.degrees(min(24, max(-24, wobble * 40 * (inBalance ? 1 : 1.6)))))
    }

    private func isLive(now: Date) -> Bool {
        !submitted && now >= turn.startAt && now < turn.deadline
    }

    private func advance(now: Date) {
        guard isLive(now: now) else { lastTick = now; return }
        guard let last = lastTick else { lastTick = now; return }
        let dt = min(0.1, now.timeIntervalSince(last))
        lastTick = now

        // Jolts pump the wobble up; it drains on its own.
        let jolt = max(0, motion.shakeG - 0.35)
        wobble = min(1, wobble + jolt * dt * joltFactor)
        wobble = max(0, wobble - dt * 0.5)

        let t = now.timeIntervalSince(turn.startAt)
        let error = abs(motion.rollDegrees - sway.center(at: t))
        if error <= effectiveHalfWidth {
            distance += GameTiming.ropeSpeed * dt
            offBalance = max(0, offBalance - dt)
        } else {
            offBalance += dt
            if offBalance >= GameTiming.ropeFallSeconds {
                fell = true
                submitted = true
                SoundPlayer.shared.play(.lose)
                session.submitRope(distanceDeci: Int((distance * 10).rounded()), fell: true, for: turn)
            }
        }
    }

    private func autoFinish() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitRope(distanceDeci: Int((distance * 10).rounded()), fell: false, for: turn)
    }

    // MARK: - Simplify

    /// A wider rope, and jolts count for less. Invisible to everyone else.
    private var baseHalfWidth: Double {
        switch session.myAssist {
        case .little: return GameTiming.ropeHalfWidthDegrees * 1.4
        case .big: return GameTiming.ropeHalfWidthDegrees * 1.9
        case .cheating: return GameTiming.ropeHalfWidthDegrees * 2.7
        default: return GameTiming.ropeHalfWidthDegrees
        }
    }

    private var joltFactor: Double {
        switch session.myAssist {
        case .little: return 1.5
        case .big: return 1.0
        case .cheating: return 0.5
        default: return 2.0
        }
    }

    /// Wobble narrows the balance band — down to 40% at full wobble.
    private var effectiveHalfWidth: Double {
        baseHalfWidth * (1 - 0.6 * wobble)
    }
}

/// Furthest along the rope takes the point.
struct RopeRevealView: View {
    let session: GameSession
    let reveal: RopeReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody made it onto the rope…"
                : "🎪 \(session.names(reveal.winners)) went the furthest!",
            rows: reveal.results
                .sorted { ($0.distanceDeci ?? -1) > ($1.distanceDeci ?? -1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🎪",
                              value: r.distanceDeci.map { deci in
                                  String(format: "%.1f m%@", Double(deci) / 10, r.fell ? " · fell" : "")
                              },
                              empty: "sat it out")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next rope"
        )
    }
}
