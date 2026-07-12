import SwiftUI

/// The ring's drift and shrink, regenerated identically on every device
/// from the turn's seed. Two summed sinusoids per axis, gently speeding
/// up, with the radius closing in over the turn.
struct SteadyPath {
    private let ax1, ax2, ay1, ay2: Double
    private let wx1, wx2, wy1, wy2: Double
    private let px1, px2, py1, py2: Double

    init(seed: UInt64) {
        var generator = SeededGenerator(seed: seed)
        func pick(_ range: ClosedRange<Double>) -> Double {
            Double.random(in: range, using: &generator)
        }
        ax1 = pick(0.10...0.16)
        ax2 = pick(0.05...0.09)
        ay1 = pick(0.10...0.16)
        ay2 = pick(0.05...0.09)
        wx1 = pick(0.35...0.60)
        wx2 = pick(0.90...1.40)
        wy1 = pick(0.35...0.60)
        wy2 = pick(0.90...1.40)
        px1 = pick(0...(2 * .pi))
        px2 = pick(0...(2 * .pi))
        py1 = pick(0...(2 * .pi))
        py2 = pick(0...(2 * .pi))
    }

    /// Ring centre in unit coordinates. The drift accelerates gently so
    /// the last stretch is the hard part.
    func center(at t: Double) -> (x: Double, y: Double) {
        let s = t * (1 + t / 90)
        let x = 0.5 + ax1 * sin(wx1 * s + px1) + ax2 * sin(wx2 * s + px2)
        let y = 0.5 + ay1 * sin(wy1 * s + py1) + ay2 * sin(wy2 * s + py2)
        return (x, y)
    }

    /// Ring radius in unit coordinates, shrinking over the turn.
    func radius(at t: Double, maxSeconds: Double) -> Double {
        let start = 0.15
        let end = 0.045
        let progress = min(1, max(0, t / maxSeconds))
        return start + (end - start) * progress
    }
}

/// One Steady Hand turn: hold your finger inside the drifting, shrinking
/// ring. The moment you slip out (or lift), your time locks in — measured
/// locally against the shared start, so latency never matters.
struct SteadyTurnView: View {
    let session: GameSession
    let turn: SteadyTurn

    @State private var touchPoint: CGPoint?
    @State private var started = false
    @State private var endedMs: Int?
    @State private var submitted = false

    private let path: SteadyPath
    private let canvasSize: CGFloat = 300
    /// Simplify: the assisted device simply draws (and judges) a bigger
    /// ring. The reveal only shows seconds, so nothing gives it away.
    private let ringScale: Double

    init(session: GameSession, turn: SteadyTurn) {
        self.session = session
        self.turn = turn
        self.path = SteadyPath(seed: turn.seed)
        switch session.myAssist {
        case nil: ringScale = 1
        case .little: ringScale = 1.35
        case .big: ringScale = 1.7
        case .cheating: ringScale = 2.1
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.02)) { context in
            let elapsed = context.date.timeIntervalSince(turn.startAt)
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                header(elapsed: elapsed)
                board(elapsed: elapsed)
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedSteady(for: turn)
            if submitted {
                endedMs = 0
                return
            }
            await monitor()
        }
    }

    @ViewBuilder
    private func header(elapsed: Double) -> some View {
        if let endedMs, endedMs > 0 {
            Text(endedMs >= Int(turn.maxSeconds * 1000)
                 ? "Made it to the end — \(timeString(endedMs))!"
                 : "Out at \(timeString(endedMs)) — waiting…")
                .font(Theme.display(22))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        } else if submitted {
            Text("Locked in — waiting…")
                .font(Theme.display(22))
        } else if elapsed < 0 {
            Text("Get ready — \(Int((-elapsed).rounded(.up)))")
                .font(Theme.display(24))
        } else if !started {
            Text("Finger in the ring!")
                .font(Theme.display(24))
                .foregroundStyle(Theme.cyan)
        } else {
            Text("\(timeString(Int(elapsed * 1000))) — stay inside…")
                .font(Theme.display(24))
                .monospacedDigit()
        }
    }

    private func board(elapsed: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface)
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
            if endedMs == nil && !submitted && elapsed >= 0 && elapsed < turn.maxSeconds {
                let center = path.center(at: elapsed)
                let radius = path.radius(at: elapsed, maxSeconds: turn.maxSeconds) * ringScale
                Circle()
                    .fill(Theme.cyan.opacity(0.14))
                    .overlay(Circle().stroke(Theme.cyan, lineWidth: 2.5))
                    .frame(width: radius * 2 * canvasSize, height: radius * 2 * canvasSize)
                    .position(x: center.x * canvasSize, y: center.y * canvasSize)
                    .shadow(color: Theme.cyan.opacity(0.35), radius: 10)
            } else if let endedMs, endedMs > 0 {
                Text(endedMs >= Int(turn.maxSeconds * 1000) ? "🏁" : "💥")
                    .font(.system(size: 56))
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    touchPoint = value.location
                    started = true
                }
                .onEnded { _ in
                    touchPoint = nil
                }
        )
    }

    /// Watches the finger against the shared path off the render loop, so
    /// state changes never happen mid view-update.
    private func monitor() async {
        while !Task.isCancelled, !submitted, endedMs == nil {
            try? await Task.sleep(for: .seconds(0.02))
            let elapsed = Date().timeIntervalSince(turn.startAt)
            guard elapsed > 0 else { continue }
            if elapsed >= turn.maxSeconds {
                if started {
                    finish(ms: Int(turn.maxSeconds * 1000))
                }
                return
            }
            // You must get in before judging starts; joining late just
            // costs you the time the clock has already run.
            guard started, elapsed > 1 else { continue }
            if !isInside(at: elapsed) {
                finish(ms: Int(elapsed * 1000))
                return
            }
        }
    }

    private func isInside(at elapsed: Double) -> Bool {
        guard let touchPoint else { return false }
        let center = path.center(at: elapsed)
        let radius = path.radius(at: elapsed, maxSeconds: turn.maxSeconds) * ringScale
        let dx = Double(touchPoint.x) / Double(canvasSize) - center.x
        let dy = Double(touchPoint.y) / Double(canvasSize) - center.y
        return (dx * dx + dy * dy).squareRoot() <= radius
    }

    private func finish(ms: Int) {
        guard endedMs == nil, !submitted else { return }
        endedMs = ms
        submitted = true
        SoundPlayer.shared.play(ms >= Int(turn.maxSeconds * 1000) ? .point : .lockin)
        session.submitSteady(survivedMs: ms, for: turn)
    }

    private func timeString(_ ms: Int) -> String {
        String(format: "%.2fs", Double(ms) / 1000)
    }
}

/// Longest hold takes the point.
struct SteadyRevealView: View {
    let session: GameSession
    let reveal: SteadyReveal

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
            return "Nobody kept a finger down…"
        }
        return "🖐️ \(session.names(reveal.winners)) lasted longest!"
    }

    private var sortedResults: [SteadyResult] {
        reveal.results.sorted { ($0.survivedMs ?? -1) > ($1.survivedMs ?? -1) }
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
                        Text("🖐️")
                    }
                    Spacer()
                    if let survivedMs = result.survivedMs {
                        Text(String(format: "%.2fs", Double(survivedMs) / 1000))
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("didn't play")
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
                    Text("Next ring in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
