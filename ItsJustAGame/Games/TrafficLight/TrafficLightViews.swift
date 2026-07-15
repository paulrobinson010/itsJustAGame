import SwiftUI

enum TrafficPhase { case green, amber, red }

/// The green→amber→red light sequence for a Traffic Light turn, built from
/// the seed so every device runs the identical lights (Simplify stretches
/// the amber and shortens the red on the assisted phone).
struct TrafficSequence {
    /// Each segment's phase and the elapsed second it ends at.
    private let segments: [(phase: TrafficPhase, end: Double)]

    init(seed: UInt64, maxSeconds: Double, amberScale: Double, redScale: Double) {
        var generator = SeededGenerator(seed: seed)
        var segs: [(TrafficPhase, Double)] = []
        var t = 0.0
        while t < maxSeconds {
            t += Double.random(in: GameTiming.trafficGreenMinSeconds...GameTiming.trafficGreenMaxSeconds, using: &generator)
            segs.append((.green, t))
            t += GameTiming.trafficAmberSeconds * amberScale
            segs.append((.amber, t))
            t += Double.random(in: GameTiming.trafficRedMinSeconds...GameTiming.trafficRedMaxSeconds, using: &generator) * redScale
            segs.append((.red, t))
        }
        segments = segs
    }

    func phase(at elapsed: Double) -> TrafficPhase {
        for seg in segments where elapsed < seg.end { return seg.phase }
        return .green
    }
}

/// One Traffic Light turn: tap like mad on green, stop the instant it turns
/// amber, and never tap on red — a tap on red is out. Most green taps over
/// 30 seconds wins. Everyone runs the same seeded lights; taps are counted
/// locally, so latency never matters.
struct TrafficTurnView: View {
    let session: GameSession
    let turn: TrafficTurn

    @State private var submitted = false
    @State private var busted = false
    @State private var taps = 0
    @State private var pop = false

    private let sequence: TrafficSequence

    init(session: GameSession, turn: TrafficTurn) {
        self.session = session
        self.turn = turn
        let scales = TrafficTurnView.scales(for: session.myAssist)
        self.sequence = TrafficSequence(seed: turn.seed, maxSeconds: turn.maxSeconds,
                                        amberScale: scales.amber, redScale: scales.red)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            let live = !submitted && now >= turn.startAt && now < turn.deadline
            let phase = live ? sequence.phase(at: now.timeIntervalSince(turn.startAt)) : .red
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · go on green, stop on amber")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now, phase: phase, live: live)
                Spacer()
                light(phase: phase, live: live)
                Spacer()
                Text("\(taps)")
                    .font(Theme.display(48)).monospacedDigit()
                    .foregroundStyle(busted ? Theme.magenta : Theme.cyan)
                Text("taps").font(Theme.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .contentShape(Rectangle())
            .onTapGesture { tap() }
        }
        .task {
            submitted = session.hasSubmittedTraffic(for: turn)
            if submitted { return }
            await autoFinish()
        }
    }

    @ViewBuilder
    private func header(now: Date, phase: TrafficPhase, live: Bool) -> some View {
        if busted {
            Text("Tapped red — out! waiting…").font(Theme.display(20)).foregroundStyle(Theme.magenta)
        } else if submitted {
            Text("\(taps) taps — waiting…").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if !live {
            Text("Time! — waiting…").font(Theme.headline)
        } else {
            switch phase {
            case .green: Text("GO — tap! 🟢").font(Theme.display(28)).foregroundStyle(.green)
            case .amber: Text("STOP! 🟡").font(Theme.display(28)).foregroundStyle(.orange)
            case .red: Text("RED — hands off! 🔴").font(Theme.display(26)).foregroundStyle(.red)
            }
        }
    }

    private func light(phase: TrafficPhase, live: Bool) -> some View {
        let colour: Color = !live ? .gray : (phase == .green ? .green : (phase == .amber ? .orange : .red))
        return Circle()
            .fill(colour.opacity(submitted && !busted ? 0.4 : 1))
            .frame(width: 220, height: 220)
            .shadow(color: colour.opacity(0.7), radius: phase == .green && live ? 26 : 8)
            .scaleEffect(pop ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.08), value: pop)
    }

    private func tap() {
        guard !submitted, !busted else { return }
        let now = Date()
        guard now >= turn.startAt, now < turn.deadline else { return }
        switch sequence.phase(at: now.timeIntervalSince(turn.startAt)) {
        case .green:
            taps += 1
            SoundPlayer.shared.play(.tick)
            pop = true
            Task { try? await Task.sleep(for: .milliseconds(80)); pop = false }
        case .amber:
            break   // the warning — no count, no harm
        case .red:
            if bustForgiven { return }   // top-level Simplify never busts
            busted = true
            submitted = true
            SoundPlayer.shared.play(.lose)
            session.submitTraffic(taps: nil, busted: true)
        }
    }

    private func autoFinish() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitTraffic(taps: taps, busted: false)
    }

    // MARK: - Simplify

    /// A longer amber warning and shorter reds make it easier to bank taps
    /// without busting; the top tier also forgives a red tap entirely. All
    /// on your own phone, invisible to everyone else.
    private static func scales(for assist: AssistLevel?) -> (amber: Double, red: Double) {
        switch assist {
        case .little: return (1.6, 1.0)
        case .big: return (2.0, 0.7)
        case .cheating: return (2.5, 0.5)
        default: return (1.0, 1.0)
        }
    }

    private var bustForgiven: Bool { session.myAssist == .cheating }
}

/// Most green taps takes the point; anyone who tapped red is out.
struct TrafficRevealView: View {
    let session: GameSession
    let reveal: TrafficReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Everyone jumped a red…"
                : "🖐️ \(session.names(reveal.winners)) tapped the most!",
            rows: reveal.results
                .sorted { sortKey($0) > sortKey($1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🖐️",
                              value: r.busted ? nil : r.taps.map { "\($0) taps" },
                              empty: r.busted ? "tapped red" : "sat it out")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next lights"
        )
    }

    /// Most taps up top; busts and no-shows sink to the bottom.
    private func sortKey(_ r: TrafficResult) -> Int {
        if r.busted { return -1 }
        return r.taps ?? -1
    }
}
