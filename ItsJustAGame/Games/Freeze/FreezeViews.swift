import SwiftUI

/// The MOVE/FREEZE schedule for a Freeze! turn, built from the seed so
/// every device calls the moments identically.
struct FreezeSchedule {
    struct Segment {
        let still: Bool
        let start: Double
        let end: Double
    }

    let segments: [Segment]

    init(seed: UInt64, maxSeconds: Double) {
        var generator = SeededGenerator(seed: seed)
        var segs: [Segment] = []
        var t = 0.0
        while t < maxSeconds {
            let move = Double.random(in: GameTiming.freezeMoveMinSeconds...GameTiming.freezeMoveMaxSeconds, using: &generator)
            segs.append(Segment(still: false, start: t, end: t + move))
            t += move
            let still = Double.random(in: GameTiming.freezeStillMinSeconds...GameTiming.freezeStillMaxSeconds, using: &generator)
            segs.append(Segment(still: true, start: t, end: t + still))
            t += still
        }
        segments = segs
    }

    func segment(at elapsed: Double) -> Segment? {
        segments.first { elapsed >= $0.start && elapsed < $0.end }
    }
}

/// One Freeze! turn: musical statues with your phone. Dance it about on
/// MOVE — the harder it moves, the faster you score. The instant FREEZE
/// flashes up, go statue: movement on a freeze burns points. Scored
/// locally, so latency never matters.
struct FreezeTurnView: View {
    let session: GameSession
    let turn: FreezeTurn

    @State private var submitted = false
    @State private var score = 0.0
    @State private var caught = false
    @State private var lastTick: Date?

    private let schedule: FreezeSchedule

    init(session: GameSession, turn: FreezeTurn) {
        self.session = session
        self.turn = turn
        self.schedule = FreezeSchedule(seed: turn.seed, maxSeconds: turn.maxSeconds)
    }

    private var motion: MotionService { MotionService.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let now = context.date
            let live = isLive(now: now)
            let seg = live ? schedule.segment(at: now.timeIntervalSince(turn.startAt)) : nil
            let still = seg?.still ?? false
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · dance, then statue")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now, live: live, still: still)
                Spacer()
                Image(systemName: still ? "figure.stand" : "figure.dance")
                    .font(.system(size: 110))
                    .foregroundStyle(!live ? Color.secondary : (still ? Theme.magenta : Theme.cyan))
                    .symbolEffect(.bounce, value: still)
                Spacer()
                Text("\(Int(score))")
                    .font(Theme.display(48)).monospacedDigit()
                    .foregroundStyle(caught ? Theme.magenta : Theme.cyan)
                    .contentTransition(.numericText())
                Text("points").font(Theme.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .background(flash(live: live, still: still))
            .onChange(of: context.date) { _, newDate in
                advance(now: newDate)
            }
        }
        .task {
            submitted = session.hasSubmittedFreeze(for: turn)
            motion.start()
            if submitted { return }
            await autoFinish()
        }
        .onDisappear { motion.stop() }
    }

    /// The whole screen tells you which mode you're in at a glance.
    private func flash(live: Bool, still: Bool) -> some View {
        (live ? (still ? Theme.magenta : Theme.cyan) : Color.clear)
            .opacity(0.12)
            .ignoresSafeArea()
    }

    @ViewBuilder
    private func header(now: Date, live: Bool, still: Bool) -> some View {
        if submitted {
            Text("\(Int(score)) points — waiting…").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if !live {
            Text("Time! — waiting…").font(Theme.headline)
        } else if still {
            Text("FREEZE! 🗿").font(Theme.display(32)).foregroundStyle(Theme.magenta)
        } else {
            Text("MOVE! 🕺").font(Theme.display(32)).foregroundStyle(Theme.cyan)
        }
    }

    private func isLive(now: Date) -> Bool {
        !submitted && now >= turn.startAt && now < turn.deadline
    }

    private func advance(now: Date) {
        guard isLive(now: now) else { lastTick = now; return }
        guard let last = lastTick else { lastTick = now; return }
        let dt = min(0.1, now.timeIntervalSince(last))
        lastTick = now

        let elapsed = now.timeIntervalSince(turn.startAt)
        guard let seg = schedule.segment(at: elapsed) else { return }
        let g = motion.shakeG
        if seg.still {
            // Human-reaction grace after the flash, then movement burns.
            guard elapsed - seg.start > graceSeconds else { return }
            if g > 0.25 {
                score = max(0, score - dt * penaltyPerSecond)
                if !caught {
                    caught = true
                    SoundPlayer.shared.play(.tick)
                    Task { try? await Task.sleep(for: .milliseconds(400)); caught = false }
                }
            }
        } else {
            // The harder you dance it, the faster you score.
            score += min(g, 2.5) * dt * 60
        }
    }

    private func autoFinish() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitFreeze(score: Int(score.rounded()), for: turn)
    }

    // MARK: - Simplify

    /// A longer grace after FREEZE flashes, and gentler penalties at the
    /// top. Invisible to everyone else.
    private var graceSeconds: Double {
        switch session.myAssist {
        case .little: return 0.7
        case .big: return 1.0
        case .cheating: return 1.5
        default: return GameTiming.freezeGraceSeconds
        }
    }

    private var penaltyPerSecond: Double {
        session.myAssist == .cheating ? 40 : 80
    }
}

/// Highest score takes the point.
struct FreezeRevealView: View {
    let session: GameSession
    let reveal: FreezeReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody moved a muscle…"
                : "🗿 \(session.names(reveal.winners)) danced it best!",
            rows: reveal.results
                .sorted { ($0.score ?? -1) > ($1.score ?? -1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🗿",
                              value: r.score.map { "\($0) pts" }, empty: "sat it out")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next dance"
        )
    }
}
