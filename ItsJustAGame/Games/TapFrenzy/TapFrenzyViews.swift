import SwiftUI

/// One Tap Frenzy turn: a shared window, tap as many times as you can.
/// Counts are local; the shared start keeps it fair.
struct FrenzyTurnView: View {
    let session: GameSession
    let turn: FrenzyTurn

    @State private var taps = 0
    @State private var submitted = false

    /// Simplify: the assisted player's window quietly runs longer. The
    /// reveal only shows a tap count, so nothing gives it away.
    private var myWindowSeconds: Double {
        switch session.myAssist {
        case nil: return turn.tapSeconds
        case .little: return turn.tapSeconds + 1.5
        case .big: return turn.tapSeconds + 3
        case .cheating: return turn.tapSeconds + GameTiming.frenzyMaxAssistExtraSeconds
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let elapsed = context.date.timeIntervalSince(turn.startAt)
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                header(elapsed: elapsed)
                tapZone(elapsed: elapsed)
                Spacer(minLength: 12)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedFrenzy(for: turn)
            await autoSubmit()
        }
    }

    @ViewBuilder
    private func header(elapsed: Double) -> some View {
        if submitted {
            Text("\(taps) taps — waiting for the others…")
                .font(Theme.display(24))
                .monospacedDigit()
        } else if elapsed < 0 {
            Text("Get ready — \(Int((-elapsed).rounded(.up)))")
                .font(Theme.display(28))
        } else {
            let remaining = max(0, myWindowSeconds - elapsed)
            Text(String(format: "%.1fs", remaining))
                .font(Theme.display(28))
                .monospacedDigit()
                .foregroundStyle(remaining < 2 ? Theme.magenta : .secondary)
        }
    }

    @ViewBuilder
    private func tapZone(elapsed: Double) -> some View {
        let active = !submitted && elapsed >= 0 && elapsed < myWindowSeconds
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(active ? Theme.cyan.opacity(0.16) : Theme.surface)
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(active ? Theme.cyan : Theme.hairline, lineWidth: active ? 2 : 1)
            VStack(spacing: 10) {
                Text("\(taps)")
                    .font(Theme.display(84))
                    .monospacedDigit()
                    .foregroundStyle(active ? Theme.cyan : .white.opacity(0.4))
                    .contentTransition(.numericText())
                Text(zoneCaption(active: active, elapsed: elapsed))
                    .font(Theme.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .padding(.horizontal, 24)
        .contentShape(Rectangle())
        .onTapGesture {
            tap()
        }
    }

    private func zoneCaption(active: Bool, elapsed: Double) -> String {
        if submitted { return "Locked in!" }
        if elapsed < 0 { return "Fingers ready…" }
        if active { return "TAP! TAP! TAP!" }
        return "Time's up!"
    }

    private func tap() {
        let elapsed = Date().timeIntervalSince(turn.startAt)
        guard !submitted, elapsed >= 0, elapsed < myWindowSeconds else { return }
        taps += 1
    }

    private func autoSubmit() async {
        guard !submitted else { return }
        let interval = turn.startAt.addingTimeInterval(myWindowSeconds).timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitFrenzy(taps: taps, for: turn)
    }
}

/// Most taps takes the point.
struct FrenzyRevealView: View {
    let session: GameSession
    let reveal: FrenzyReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text("Turn \(reveal.turn)")
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
            return "Nobody tapped at all…"
        }
        let best = reveal.winners.compactMap { slot in
            reveal.results.first { $0.slot == slot }?.taps
        }.max() ?? 0
        return "👏 \(session.names(reveal.winners)) hammered out \(best) taps!"
    }

    private var sortedResults: [FrenzyResult] {
        reveal.results.sorted { ($0.taps ?? -1) > ($1.taps ?? -1) }
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
                        Text("👏")
                    }
                    Spacer()
                    if let taps = result.taps {
                        Text("\(taps) taps")
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("didn't tap")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .card()
        .padding(.horizontal, 24)
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
                    Text("Next frenzy in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
