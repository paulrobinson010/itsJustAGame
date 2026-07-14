import SwiftUI

/// One Traffic Light turn: the light holds red for a random spell, then turns
/// green — tap the instant it does. Tapping on red is a false start (out for
/// the turn). Reaction is timed locally against the shared green moment, so
/// latency never matters.
struct TrafficTurnView: View {
    let session: GameSession
    let turn: TrafficTurn

    @State private var submitted = false
    @State private var falseStart = false
    @State private var reactionMs: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let now = context.date
            let live = !submitted && now >= turn.startAt && now < turn.deadline
            let green = now >= turn.greenAt
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · go on green")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.3)
                header(now: now, green: green)
                Spacer()
                light(now: now, green: green, live: live)
                Spacer()
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
    private func header(now: Date, green: Bool) -> some View {
        if submitted {
            if falseStart {
                Text("Jumped the light! — waiting…").font(Theme.display(20)).foregroundStyle(Theme.magenta)
            } else if let ms = reactionMs {
                Text("\(ms) ms! — waiting…").font(Theme.display(22)).foregroundStyle(Theme.cyan)
            } else {
                Text("Too slow — waiting…").font(Theme.headline)
            }
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if green {
            Text("GO! 🟢 tap!").font(Theme.display(30)).foregroundStyle(.green)
        } else {
            Text("Wait for green…").font(Theme.display(22)).foregroundStyle(Theme.magenta)
        }
    }

    private func light(now: Date, green: Bool, live: Bool) -> some View {
        // Amber warning in the run-up to green (longer for the gentlest
        // Simplify tier); tapping on amber still counts as jumping.
        let amber = !green && now >= turn.greenAt.addingTimeInterval(-amberLead)
        let colour: Color = green ? .green : (amber ? .orange : .red)
        let countdown: Int? = showsCountdown && !green ? Int(max(0, turn.greenAt.timeIntervalSince(now)).rounded(.up)) : nil
        return ZStack {
            Circle()
                .fill(colour.opacity(submitted ? 0.4 : 1))
                .frame(width: 220, height: 220)
                .shadow(color: colour.opacity(0.7), radius: green ? 30 : 8)
            if let countdown, countdown > 0 {
                Text("\(countdown)")
                    .font(.system(size: 90, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
            }
        }
    }

    private func tap() {
        guard !submitted else { return }
        let now = Date()
        guard now >= turn.startAt, now < turn.deadline else { return }
        submitted = true
        if now < turn.greenAt {
            falseStart = true
            SoundPlayer.shared.play(.lose)
            session.submitTraffic(reactionMs: nil, falseStart: true, for: turn)
        } else {
            let raw = now.timeIntervalSince(turn.greenAt) * 1000
            let ms = max(0, Int((raw * assistScale).rounded()))
            reactionMs = ms
            SoundPlayer.shared.play(.point)
            session.submitTraffic(reactionMs: ms, falseStart: false, for: turn)
        }
    }

    private func autoFinish() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        // Never tapped — stop; the host records "too slow" for us.
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
    }

    // MARK: - Simplify

    /// Quietly shaves your reaction time — invisible at the reveal.
    private var assistScale: Double {
        switch session.myAssist {
        case .little: return 0.85
        case .big: return 0.7
        case .cheating: return 0.55
        default: return 1.0
        }
    }

    /// How long the amber warning shows before green.
    private var amberLead: Double {
        session.myAssist == nil ? 0.4 : 0.8
    }

    /// Levels 2–3 show a live countdown to green.
    private var showsCountdown: Bool {
        guard let level = session.myAssist else { return false }
        return level >= .big
    }
}

/// Fastest off the mark takes the point; jumpers don't count.
struct TrafficRevealView: View {
    let session: GameSession
    let reveal: TrafficReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody made it…"
                : "🚦 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") quickest!",
            rows: reveal.results
                .sorted { sortKey($0) < sortKey($1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🚦",
                              value: r.falseStart ? nil : r.reactionMs.map { "\($0) ms" },
                              empty: r.falseStart ? "jumped" : "too slow")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next light"
        )
    }

    /// Valid reactions first (fastest up), then jumps/misses.
    private func sortKey(_ r: TrafficResult) -> Int {
        if r.falseStart { return 1_000_000 }
        return r.reactionMs ?? 999_999
    }
}
