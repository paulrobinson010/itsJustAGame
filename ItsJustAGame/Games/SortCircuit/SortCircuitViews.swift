import SwiftUI

/// One Sort Circuit turn: nine numbered tiles scattered identically on
/// every device (same seed), tap 1→9 as fast as you can. Time runs
/// locally from the shared start timestamp; mistakes add a second.
struct SortTurnView: View {
    let session: GameSession
    let turn: SortTurn

    @State private var nextValue = 1
    @State private var done: Set<Int> = []
    @State private var penaltyMs = 0
    @State private var wrongFlash: Int?
    @State private var resultMs: Int?
    @State private var submitted = false

    private let positions: [(x: Double, y: Double)]

    init(session: GameSession, turn: SortTurn) {
        self.session = session
        self.turn = turn
        self.positions = SharedLayout.tilePositions(seed: turn.seed, count: turn.tileCount)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            VStack(spacing: 12) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · mistakes cost 1s")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                header(now: now)
                board(now: now)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedSort(for: turn)
            if submitted {
                resultMs = 0
            }
        }
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        if let resultMs, resultMs > 0 {
            Text("You: \(timeString(resultMs)) — waiting…")
                .font(Theme.display(24))
        } else if submitted {
            Text("Locked in — waiting…")
                .font(Theme.display(24))
        } else if now < turn.startAt {
            Text("Get ready…")
                .font(Theme.display(24))
        } else if now >= turn.deadline {
            Text("Time's up — waiting for the reveal…")
                .font(Theme.headline)
        } else {
            let elapsed = Int(now.timeIntervalSince(turn.startAt) * 1000) + penaltyMs
            HStack(spacing: 12) {
                Text("Find \(nextValue)")
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.cyan)
                Text(timeString(elapsed))
                    .font(Theme.display(24))
                    .monospacedDigit()
                    .foregroundStyle(penaltyMs > 0 ? Theme.magenta : .white)
            }
        }
    }

    private func board(now: Date) -> some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: size, height: size)
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
                    .frame(width: size, height: size)
                if now >= turn.startAt {
                    ForEach(1...turn.tileCount, id: \.self) { value in
                        tile(value: value)
                            .position(
                                x: positions[value - 1].x * size,
                                y: positions[value - 1].y * size
                            )
                    }
                } else {
                    Text("…")
                        .font(Theme.display(32))
                        .foregroundStyle(.secondary)
                        .position(x: size / 2, y: size / 2)
                }
            }
            .frame(width: size, height: size)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 24)
    }

    private func tile(value: Int) -> some View {
        let isDone = done.contains(value)
        return Text("\(value)")
            .font(Font.custom(Theme.BrandFont.bold, size: 22))
            .monospacedDigit()
            .foregroundStyle(isDone ? Color.white.opacity(0.25) : .white)
            .frame(width: 54, height: 54)
            .background(
                isDone ? Theme.quietFill : Color.white.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        wrongFlash == value ? Theme.magenta : Theme.hairline,
                        lineWidth: wrongFlash == value ? 2.5 : 1
                    )
            )
            .onTapGesture { tap(value: value) }
    }

    private func tap(value: Int) {
        let now = Date()
        guard !submitted,
              now >= turn.startAt,
              now < turn.deadline,
              !done.contains(value) else { return }
        if value == nextValue {
            SoundPlayer.shared.play(.tick)
            done.insert(value)
            nextValue += 1
            if nextValue > turn.tileCount {
                let elapsed = Int(now.timeIntervalSince(turn.startAt) * 1000) + penaltyMs
                resultMs = elapsed
                submitted = true
                SoundPlayer.shared.play(.lockin)
                session.submitSort(
                    elapsedMs: elapsed,
                    mistakes: penaltyMs / GameTiming.sortPenaltyMs,
                    for: turn
                )
            }
        } else {
            penaltyMs += GameTiming.sortPenaltyMs
            wrongFlash = value
            Task {
                try? await Task.sleep(for: .seconds(0.25))
                if wrongFlash == value {
                    wrongFlash = nil
                }
            }
        }
    }

    private func timeString(_ ms: Int) -> String {
        String(format: "%.2fs", Double(ms) / 1000)
    }
}

/// Fastest clean(ish) run takes the point.
struct SortRevealView: View {
    let session: GameSession
    let reveal: SortReveal

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
            return "Nobody finished the circuit…"
        }
        return "🔢 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") fastest!"
    }

    private var sortedResults: [SortResult] {
        reveal.results.sorted { ($0.elapsedMs ?? .max) < ($1.elapsedMs ?? .max) }
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
                        Text("🔢")
                    }
                    Spacer()
                    if let elapsedMs = result.elapsedMs {
                        Text(String(format: "%.2fs", Double(elapsedMs) / 1000))
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if result.mistakes > 0 {
                            Text("(\(result.mistakes) slip\(result.mistakes == 1 ? "" : "s"))")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.magenta)
                        }
                    } else {
                        Text("didn't finish")
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
                    Text("Next circuit in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
