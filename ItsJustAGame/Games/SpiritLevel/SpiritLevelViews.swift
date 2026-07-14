import SwiftUI

/// The target zone's drift, regenerated identically on every device from
/// the turn's seed. The centre angle starts at 0 (so you can catch it) and
/// wanders faster and faster, so holding gets harder the longer you last.
struct LevelDrift {
    private let a1, a2, w1, w2: Double

    init(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        func pick(_ range: ClosedRange<Double>) -> Double {
            Double.random(in: range, using: &generator)
        }
        a1 = pick(13...18)   // degrees
        a2 = pick(6...10)
        w1 = pick(0.6...0.9)
        w2 = pick(1.2...1.7)
    }

    /// Centre of the level zone, in degrees, at elapsed time `t` seconds.
    /// The time base grows with t², so the zone barely moves for the first
    /// couple of seconds and then speeds up — an easy start, a frantic end.
    func center(at t: Double) -> Double {
        let s = t * t / 12
        return a1 * sin(w1 * s) + a2 * sin(w2 * s)
    }
}

/// One Spirit Level turn: keep the bubble between the two markers — but the
/// markers drift, faster and faster. The clock runs as long as you can
/// stay inside; the moment you slip out, your time locks in. Longest hold
/// wins. Measured on each device, so latency never matters.
struct LevelTurnView: View {
    let session: GameSession
    let turn: LevelTurn

    @State private var submitted = false
    @State private var heldMs = 0
    /// Device-local "GO" moment, so the run-up is timed on this phone.
    @State private var goAt: Date?
    /// When the current hold began (nil = not currently holding).
    @State private var holdStartAt: Date?
    /// When the bubble left the zone mid-hold (nil = inside). A brief dip is
    /// forgiven; staying out past the grace ends the hold.
    @State private var leftAt: Date?

    private let drift: LevelDrift

    init(session: GameSession, turn: LevelTurn) {
        self.session = session
        self.turn = turn
        self.drift = LevelDrift(seed: turn.seed)
    }

    private var motion: MotionService { MotionService.shared }

    private var playEndsAt: Date? {
        goAt?.addingTimeInterval(turn.maxSeconds)
    }

    private let slipGrace: Double = 0.3

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let now = context.date
            let roll = motion.rollDegrees
            let center = zoneCenter(now: now)
            let inZone = abs(roll - center) <= zoneHalfWidth
            let playing = isPlaying(now: now)
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · stay in the zone")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now, playing: playing, inZone: inZone)
                Spacer(minLength: 8)
                gauge(roll: roll, center: center, inZone: inZone && playing)
                Spacer(minLength: 8)
                timer(now: now, playing: playing)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .onChange(of: context.date) { _, newDate in
                advance(now: newDate, roll: motion.rollDegrees)
            }
        }
        .task {
            submitted = session.hasSubmittedLevel(for: turn)
            motion.start()
            goAt = Date().addingTimeInterval(GameTiming.tiltCountdownSeconds)
            await autoFinish()
        }
        .onDisappear { motion.stop() }
    }

    private func isPlaying(now: Date) -> Bool {
        guard let go = goAt, let end = playEndsAt, !submitted else { return false }
        return now >= go && now < end
    }

    /// Where the level zone's centre sits right now, in degrees.
    private func zoneCenter(now: Date) -> Double {
        guard let go = goAt else { return 0 }
        return drift.center(at: max(0, now.timeIntervalSince(go)))
    }

    /// The hold time to show right now: the live streak while holding, else
    /// the value locked in.
    private func currentMs(now: Date) -> Int {
        if submitted { return heldMs }
        if let start = holdStartAt { return Int(max(0, now.timeIntervalSince(start)) * 1000) }
        return 0
    }

    @ViewBuilder
    private func header(now: Date, playing: Bool, inZone: Bool) -> some View {
        if submitted {
            Text("Held \(secondsText(heldMs)) — waiting…")
                .font(Theme.display(22))
                .foregroundStyle(heldMs > 0 ? .white : Theme.magenta)
        } else if !motion.isAvailable {
            Text("This game needs a real device")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.magenta)
        } else if goAt == nil {
            Text("Get ready…")
                .font(Theme.display(24))
        } else if let go = goAt, now < go {
            let count = Int(go.timeIntervalSince(now).rounded(.up))
            Text(count > 0 ? "\(count)" : "GO!")
                .font(Theme.display(count > 0 ? 64 : 40))
                .foregroundStyle(Theme.magenta)
                .contentTransition(.numericText())
        } else if playing {
            if holdStartAt == nil {
                Text("Catch the zone to start the clock")
                    .font(Theme.display(18))
                    .foregroundStyle(.secondary)
            } else {
                Text(inZone ? "Stay with it!" : "Chase it back!")
                    .font(Theme.display(22))
                    .foregroundStyle(inZone ? Color.green : Theme.magenta)
            }
        } else {
            Text("Time's up — waiting for the reveal…")
                .font(Theme.headline)
        }
    }

    private func gauge(roll: Double, center: Double, inZone: Bool) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let bubbleX = position(roll) * w
            let leftX = position(center - zoneHalfWidth) * w
            let rightX = position(center + zoneHalfWidth) * w
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surface)
                    .frame(height: 56)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                // The level zone between the two markers.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill((inZone ? Color.green : Theme.cyan).opacity(0.16))
                    .frame(width: max(0, rightX - leftX), height: 52)
                    .position(x: (leftX + rightX) / 2, y: h / 2)
                // The two markers.
                ForEach([leftX, rightX], id: \.self) { markX in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.magenta)
                        .frame(width: 3, height: 64)
                        .position(x: markX, y: h / 2)
                }
                // The bubble.
                Circle()
                    .fill(inZone ? Color.green : Theme.cyan)
                    .frame(width: 40, height: 40)
                    .shadow(color: (inZone ? Color.green : Theme.cyan).opacity(0.6), radius: 8)
                    .position(x: min(max(bubbleX, 20), w - 20), y: h / 2)
            }
            .frame(height: h)
        }
        .frame(height: 90)
        .padding(.horizontal, 24)
    }

    private func timer(now: Date, playing: Bool) -> some View {
        let ms = currentMs(now: now)
        let holding = holdStartAt != nil && !submitted && playing
        return Text(secondsText(ms))
            .font(Theme.display(48)).monospacedDigit()
            .foregroundStyle(holding ? Color.green : .primary)
    }

    // MARK: - Hold logic

    private func advance(now: Date, roll: Double) {
        guard let go = goAt, let end = playEndsAt, !submitted else { return }
        guard now >= go else { return }
        if now >= end {
            finish(ms: holdStartAt.map { Int(end.timeIntervalSince($0) * 1000) } ?? heldMs)
            return
        }
        let center = drift.center(at: now.timeIntervalSince(go))
        let inZone = abs(roll - center) <= zoneHalfWidth
        if inZone {
            leftAt = nil
            if holdStartAt == nil { holdStartAt = now }
        } else if let start = holdStartAt {
            if leftAt == nil {
                leftAt = now
            } else if now.timeIntervalSince(leftAt!) > slipGrace {
                // Slipped out for good — lock the time at the moment we left.
                finish(ms: Int(leftAt!.timeIntervalSince(start) * 1000))
            }
        }
    }

    private func finish(ms: Int) {
        guard !submitted else { return }
        submitted = true
        heldMs = max(0, ms)
        SoundPlayer.shared.play(heldMs > 0 ? .lockin : .lose)
        session.submitLevel(heldMs: heldMs, for: turn)
    }

    private func autoFinish() async {
        let end = playEndsAt ?? Date().addingTimeInterval(GameTiming.tiltCountdownSeconds + turn.maxSeconds)
        let interval = end.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        finish(ms: holdStartAt.map { Int(end.timeIntervalSince($0) * 1000) } ?? 0)
    }

    // MARK: - Display helpers

    private func secondsText(_ ms: Int) -> String {
        String(format: "%.1fs", Double(ms) / 1000)
    }

    /// Maps a roll angle onto the 0…1 bar (±45° full scale).
    private func position(_ deg: Double) -> Double {
        min(max((deg + 45) / 90, 0), 1)
    }

    // MARK: - Simplify

    /// Half the gap between the markers, in degrees. Simplify widens it, so
    /// an assisted player finds it easier to keep the bubble inside.
    private var zoneHalfWidth: Double {
        let base = GameTiming.levelZoneDegrees
        switch session.myAssist {
        case .little: return base * 1.8
        case .big: return base * 2.6
        case .cheating: return base * 3.6
        default: return base
        }
    }
}

/// Longest hold takes the point.
struct LevelRevealView: View {
    let session: GameSession
    let reveal: LevelReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody held it…"
                : "🫧 \(session.names(reveal.winners)) held on longest!",
            rows: reveal.results
                .sorted { ($0.heldMs ?? -1) > ($1.heldMs ?? -1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🫧",
                              value: r.heldMs.map { String(format: "%.1fs", Double($0) / 1000) },
                              empty: "never levelled")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next hold"
        )
    }
}
