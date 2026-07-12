import SwiftUI

/// One Ten Seconds turn: the clock counts up visibly, hides, and you tap
/// when you think it hits the target. Elapsed time is measured locally
/// against the shared start timestamp, so network latency never matters.
/// Your own time stays hidden until the reveal.
struct ClockTurnView: View {
    let session: GameSession
    let turn: ClockTurn

    @State private var submitted = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let elapsed = context.date.timeIntervalSince(turn.startAt)
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text("Tap at exactly \(Int(turn.targetSeconds)) seconds")
                    .font(Theme.display(24))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
                center(elapsed: elapsed)
                Spacer()
                if !submitted && elapsed >= 0 && elapsed < turn.maxSeconds {
                    Text("Tap anywhere when you think it's time")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 16)
                }
            }
            .padding(.top, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture { handleTap() }
        .task {
            submitted = session.hasSubmittedClockTap(for: turn)
            await playVisibleTicks()
        }
    }

    @ViewBuilder
    private func center(elapsed: TimeInterval) -> some View {
        if submitted {
            VStack(spacing: 12) {
                Text("🔒")
                    .font(.system(size: 52))
                Text("Locked in!")
                    .font(Theme.display(28))
                Text("No peeking — times at the reveal.")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if elapsed < 0 {
            Text("Get ready…")
                .font(Theme.display(28))
        } else if elapsed <= turn.visibleSeconds {
            Text(String(format: "%.2f", elapsed))
                .font(Theme.display(64))
                .monospacedDigit()
                .foregroundStyle(Theme.cyan)
        } else if elapsed >= turn.maxSeconds {
            VStack(spacing: 12) {
                Text("Too long — no tap.")
                    .font(Theme.display(24))
                Text("Waiting for the reveal…")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 16) {
                Text("?.??")
                    .font(Theme.display(64))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.15))
                HStack(spacing: 8) {
                    Circle()
                        .fill(Theme.magenta)
                        .frame(width: 10, height: 10)
                        .shadow(color: Theme.magenta.opacity(0.7), radius: 10)
                    Text("Keep counting…")
                        .font(Theme.headline)
                }
            }
        }
    }

    private func handleTap() {
        guard !submitted else { return }
        let elapsed = Date().timeIntervalSince(turn.startAt)
        guard elapsed > 0, elapsed < turn.maxSeconds else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitClockTap(elapsedMs: Int(elapsed * 1000), for: turn)
    }

    /// Audible pips while the clock is visible — a rhythm to carry with you.
    private func playVisibleTicks() async {
        for second in 1...Int(turn.visibleSeconds) {
            let at = turn.startAt.addingTimeInterval(Double(second))
            let wait = at.timeIntervalSinceNow
            guard wait > -0.3 else { continue }
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
            }
            guard !Task.isCancelled, !submitted else { return }
            SoundPlayer.shared.play(.tick)
        }
    }
}

/// Everyone's time against the target, closest first.
struct ClockRevealView: View {
    let session: GameSession
    let reveal: ClockReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text("Target \(String(format: "%.2f", reveal.targetSeconds))s")
                .font(Theme.kicker)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            Text(headline)
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            resultsList
            footer
            Spacer()
        }
        .padding(.top, 8)
    }

    private var headline: String {
        if reveal.winners.isEmpty {
            return "Nobody tapped that time…"
        }
        return "⏱️ \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!"
    }

    private var sortedResults: [ClockResult] {
        reveal.results.sorted { ($0.errorMs ?? .max) < ($1.errorMs ?? .max) }
    }

    private var resultsList: some View {
        VStack(spacing: 8) {
            ForEach(sortedResults) { result in
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.color(result.slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(result.slot))
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    if reveal.winners.contains(result.slot) {
                        Text("⏱️")
                    }
                    Spacer()
                    if let elapsed = result.elapsedMs {
                        Text(String(format: "%.2fs", Double(elapsed) / 1000))
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text(signedDiff(elapsed))
                            .font(Theme.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("no tap")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
        .padding(.horizontal, 24)
    }

    private func signedDiff(_ elapsedMs: Int) -> String {
        let diff = Double(elapsedMs) / 1000 - reveal.targetSeconds
        return String(format: "%+.2f", diff)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if !reveal.roundWinners.isEmpty {
                    Text("🏆 \(session.names(reveal.roundWinners)) \(reveal.roundWinners.count == 1 ? "wins" : "win") the round!")
                        .font(Theme.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let next = reveal.nextAt {
                    let remaining = Int(max(0, next.timeIntervalSince(context.date)).rounded(.up))
                    Text("Next target in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
