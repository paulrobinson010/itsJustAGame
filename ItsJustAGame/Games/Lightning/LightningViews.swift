import SwiftUI

/// One Lightning turn: a dark waiting screen, then the whole screen
/// flashes cyan at the host-rolled shared timestamp. Reaction time is
/// measured locally against that timestamp, so network latency never
/// affects fairness. Tapping early is a false start.
struct FlashTurnView: View {
    let session: GameSession
    let turn: FlashTurn

    private enum LocalResult: Equatable {
        case falseStart
        case tapped(ms: Int)
    }

    @State private var result: LocalResult?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            let flashing = now >= turn.flashAt && result == nil && now <= turn.deadline
            ZStack {
                (flashing ? Theme.cyan : Theme.background)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                        .opacity(flashing ? 0 : 1)
                    Text("Flash \(turn.turn)")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(1.5)
                        .opacity(flashing ? 0 : 1)
                    Spacer()
                    center(now: now, flashing: flashing)
                    Spacer()
                }
                .padding(.top, 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { handleTap() }
        }
    }

    @ViewBuilder
    private func center(now: Date, flashing: Bool) -> some View {
        switch result {
        case .falseStart:
            VStack(spacing: 12) {
                Text("🚫")
                    .font(.system(size: 56))
                Text("False start!")
                    .font(Theme.display(30))
                    .foregroundStyle(Theme.magenta)
                Text("You jumped early — you can't win this flash.")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .tapped(let ms):
            VStack(spacing: 12) {
                Text("⚡")
                    .font(.system(size: 56))
                Text("\(ms) ms")
                    .font(Theme.display(44))
                    .monospacedDigit()
                Text("Waiting for the others…")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
            }
        case nil:
            if flashing {
                Text("TAP!")
                    .font(Theme.display(72))
                    .foregroundStyle(Theme.ink)
            } else if now > turn.deadline {
                VStack(spacing: 12) {
                    Text("Too slow — no tap.")
                        .font(Theme.display(24))
                    Text("Waiting for the reveal…")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    Circle()
                        .fill(Theme.magenta)
                        .frame(width: 14, height: 14)
                        .shadow(color: Theme.magenta.opacity(0.7), radius: 12)
                    Text("Wait for it…")
                        .font(Theme.display(28))
                    Text("Tap the moment the screen flashes.")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func handleTap() {
        guard result == nil else { return }
        let tapDate = Date()
        if tapDate < turn.flashAt {
            result = .falseStart
            session.submitReaction(elapsedMs: nil, falseStart: true, for: turn)
        } else if tapDate <= turn.deadline.addingTimeInterval(1) {
            let ms = Int(tapDate.timeIntervalSince(turn.flashAt) * 1000)
            result = .tapped(ms: ms)
            session.submitReaction(elapsedMs: ms, falseStart: false, for: turn)
        }
    }
}

/// The reveal: everyone's reaction time ranked, false starts shamed.
struct FlashRevealView: View {
    let session: GameSession
    let reveal: FlashReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
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
            return "No valid taps that time…"
        }
        return "⚡ \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "takes" : "take") the point!"
    }

    private var sortedResults: [FlashResult] {
        reveal.results.sorted { a, b in
            rankKey(a) < rankKey(b)
        }
    }

    /// Valid taps by speed, then no-taps, then false starts.
    private func rankKey(_ result: FlashResult) -> Int {
        if result.falseStart { return 2_000_000 + result.slot }
        guard let ms = result.elapsedMs else { return 1_000_000 + result.slot }
        return ms
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
                        Text("⚡")
                    }
                    Spacer()
                    if result.falseStart {
                        Text("false start")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.magenta)
                    } else if let ms = result.elapsedMs {
                        Text("\(ms) ms")
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
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
                    Text("Next flash in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
