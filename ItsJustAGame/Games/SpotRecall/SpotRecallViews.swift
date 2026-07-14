import SwiftUI

/// One Spot Recall turn: dots flash on a square canvas (identical on every
/// device from the seed), then vanish. Tap where each one was; the device
/// scores your average distance from the real spots. Measured locally, so
/// latency never matters.
struct SpotTurnView: View {
    let session: GameSession
    let turn: SpotTurn

    @State private var taps: [CGPoint] = []
    @State private var submitted = false
    @State private var canvasSide: Double = 300

    /// The real dot positions, as fractions (0–1) of the canvas, rebuilt
    /// identically everywhere from the turn's seed.
    private let dots: [CGPoint]

    init(session: GameSession, turn: SpotTurn) {
        self.session = session
        self.turn = turn
        self.dots = SpotTurnView.layout(seed: turn.seed, count: turn.dotCount)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let memorizing = now >= turn.startAt && now < turn.recallStart
            let recalling = !submitted && now >= turn.recallStart && now < turn.deadline
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · \(turn.dotCount) dots")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.3)
                header(now: now, memorizing: memorizing, recalling: recalling)
                canvas(memorizing: memorizing, recalling: recalling)
                if recalling {
                    HStack(spacing: 12) {
                        Button {
                            taps = []
                        } label: {
                            Label("Clear", systemImage: "eraser")
                                .font(Theme.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Button {
                            submit()
                        } label: {
                            Label("Lock it in", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(taps.isEmpty)
                    }
                    .padding(.horizontal, 24)
                }
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedSpot(for: turn)
            if submitted { return }
            await autoSubmit()
        }
    }

    @ViewBuilder
    private func header(now: Date, memorizing: Bool, recalling: Bool) -> some View {
        if submitted {
            Text("Locked in — waiting…").font(Theme.display(20))
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if memorizing {
            Text("Remember the spots! 👀").font(Theme.display(24)).foregroundStyle(Theme.magenta)
        } else if recalling {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            let left = turn.dotCount - taps.count
            Text(left > 0 ? "Tap the \(left) spot\(left == 1 ? "" : "s") · \(remaining)s" : "Adjust or lock in · \(remaining)s")
                .font(Theme.display(20)).foregroundStyle(Theme.cyan)
        } else {
            Text("Time's up — waiting…").font(Theme.headline)
        }
    }

    private func canvas(memorizing: Bool, recalling: Bool) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                // The real dots, shown while memorising (and faintly during
                // recall for the Simplify tiers).
                if memorizing || guideOpacity > 0 {
                    ForEach(0..<dots.count, id: \.self) { i in
                        Circle()
                            .fill(Theme.magenta.opacity(memorizing ? 1 : guideOpacity))
                            .frame(width: 22, height: 22)
                            .position(x: dots[i].x * side, y: dots[i].y * side)
                    }
                }
                // Your taps.
                ForEach(0..<taps.count, id: \.self) { i in
                    Circle()
                        .stroke(session.color(session.mySlot), lineWidth: 3)
                        .frame(width: 24, height: 24)
                        .position(taps[i])
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard recalling, !submitted, taps.count < turn.dotCount else { return }
                canvasSide = side
                taps.append(location)
            }
            .onAppear { canvasSide = side }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 24)
    }

    /// Mean distance from each real dot to the nearest tap, as a fraction of
    /// the canvas. Lower is better; missing taps read as far away.
    private func meanError() -> Double {
        guard canvasSide > 0, !taps.isEmpty else { return 1.0 }
        let tapFractions = taps.map { CGPoint(x: $0.x / canvasSide, y: $0.y / canvasSide) }
        var total = 0.0
        for dot in dots {
            let nearest = tapFractions.map { hypot($0.x - dot.x, $0.y - dot.y) }.min() ?? 1.0
            total += nearest
        }
        return total / Double(dots.count)
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        guard !taps.isEmpty else { return }   // no taps → host records "no answer"
        SoundPlayer.shared.play(.lockin)
        session.submitSpot(errorPerMille: Int((meanError() * 1000).rounded()), for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submit()
    }

    // MARK: - Simplify

    /// A faint trace of the real dots left up during recall (0 = off).
    private var guideOpacity: Double {
        switch session.myAssist {
        case .little: return 0.12
        case .big: return 0.25
        case .cheating: return 0.55
        default: return 0
        }
    }

    /// Dot positions as canvas fractions, spread out with a margin and a
    /// minimum gap so they never sit on top of each other.
    static func layout(seed: UInt64, count: Int) -> [CGPoint] {
        var generator = SeededGenerator(seed: seed)
        var points: [CGPoint] = []
        var attempts = 0
        while points.count < count && attempts < 400 {
            attempts += 1
            let p = CGPoint(
                x: Double.random(in: 0.14...0.86, using: &generator),
                y: Double.random(in: 0.14...0.86, using: &generator)
            )
            if points.allSatisfy({ hypot($0.x - p.x, $0.y - p.y) > 0.2 }) {
                points.append(p)
            }
        }
        return points
    }
}

/// Closest to the real spots takes the point.
struct SpotRevealView: View {
    let session: GameSession
    let reveal: SpotReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody remembered…"
                : "🎯 \(session.names(reveal.winners)) remembered best!",
            rows: reveal.results
                .sorted { ($0.errorPerMille ?? .max) < ($1.errorPerMille ?? .max) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🎯",
                              value: r.errorPerMille.map { "\($0 / 10)% off" }, empty: "no taps")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next round"
        )
    }
}
