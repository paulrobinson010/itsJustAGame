import SwiftUI

/// One Trace It turn: a winding line (identical everywhere from the seed) is
/// shown; trace along it with one finger. The device scores how closely your
/// stroke follows the line and submits that number, closest wins. Measured
/// locally, so latency never matters.
struct TraceTurnView: View {
    let session: GameSession
    let turn: TraceTurn

    @State private var stroke: [CGPoint] = []
    @State private var submitted = false
    @State private var canvasSide: Double = 300

    /// The line to trace, as canvas fractions (0–1), rebuilt identically
    /// everywhere from the seed.
    private let path: [CGPoint]

    init(session: GameSession, turn: TraceTurn) {
        self.session = session
        self.turn = turn
        self.path = TraceTurnView.line(seed: turn.seed)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let tracing = !submitted && now >= turn.startAt && now < turn.deadline
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · follow the line")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.3)
                header(now: now, tracing: tracing)
                canvas(tracing: tracing)
                if tracing {
                    HStack(spacing: 12) {
                        Button {
                            stroke = []
                        } label: {
                            Label("Clear", systemImage: "eraser")
                                .font(Theme.subheadline).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Button {
                            submit()
                        } label: {
                            Label("Lock it in", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(stroke.count < 3)
                    }
                    .padding(.horizontal, 24)
                }
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedTrace(for: turn)
            if submitted { return }
            await autoSubmit()
        }
    }

    @ViewBuilder
    private func header(now: Date, tracing: Bool) -> some View {
        if submitted {
            Text("Locked in — waiting…").font(Theme.display(20))
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if tracing {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("Trace the line! · \(remaining)s").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else {
            Text("Time's up — waiting…").font(Theme.headline)
        }
    }

    private func canvas(tracing: Bool) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                // The line to trace. With Simplify it fattens into a visible
                // tolerance band — anywhere on the paint counts as on the line.
                linePath(side: side)
                    .stroke(Theme.magenta.opacity(scoreTolerance > 0 ? 0.28 : 0.9),
                            style: StrokeStyle(lineWidth: guideWidth(side: side), lineCap: .round, lineJoin: .round,
                                               dash: scoreTolerance > 0 ? [] : [2, 10]))

                // Your trace.
                strokePath
                    .stroke(session.color(session.mySlot),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard tracing, !submitted else { return }
                        canvasSide = side
                        stroke.append(value.location)
                    }
            )
            .onAppear { canvasSide = side }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 24)
    }

    private func linePath(side: Double) -> Path {
        var p = Path()
        guard let first = path.first else { return p }
        p.move(to: CGPoint(x: first.x * side, y: first.y * side))
        for pt in path.dropFirst() { p.addLine(to: CGPoint(x: pt.x * side, y: pt.y * side)) }
        return p
    }

    private var strokePath: Path {
        var p = Path()
        guard let first = stroke.first else { return p }
        p.move(to: first)
        for pt in stroke.dropFirst() { p.addLine(to: pt) }
        return p
    }

    /// How much bigger the reported error is than the raw canvas distance —
    /// a precise trace should still cost you, so scoring bites.
    private static let harshGain = 3.0

    /// Error between the trace and the line, as a fraction of the canvas.
    /// It blends the average deviation (both ways, a Chamfer distance) with
    /// your single worst stray — so one careless excursion can't be averaged
    /// away — then multiplies by a gain so scoring is unforgiving. Simplify
    /// widens the tolerance band (see `scoreTolerance`): anything within the
    /// painted line reads as zero error. Lower is better.
    private func meanError() -> Double {
        guard canvasSide > 0, stroke.count >= 3 else { return 1.0 }
        let mine: [CGPoint] = stroke.map { CGPoint(x: Double($0.x) / canvasSide, y: Double($0.y) / canvasSide) }
        let tol = scoreTolerance

        func nearest(_ p: CGPoint, in pts: [CGPoint]) -> Double {
            var best = Double.greatestFiniteMagnitude
            for q in pts {
                let dx = Double(p.x - q.x)
                let dy = Double(p.y - q.y)
                let d = (dx * dx + dy * dy).squareRoot()
                if d < best { best = d }
            }
            if best == .greatestFiniteMagnitude { return 1.0 }
            return max(0, best - tol)   // within the painted line = on the line
        }

        var sumToLine = 0.0
        var maxToLine = 0.0
        for t in path {
            let d = nearest(t, in: mine)
            sumToLine += d
            if d > maxToLine { maxToLine = d }
        }
        var sumToMine = 0.0
        var maxToMine = 0.0
        for m in mine {
            let d = nearest(m, in: path)
            sumToMine += d
            if d > maxToMine { maxToMine = d }
        }
        let meanTerm = (sumToLine / Double(path.count) + sumToMine / Double(mine.count)) / 2
        let tailTerm = max(maxToLine, maxToMine)   // your single worst stray
        let raw = meanTerm * 0.6 + tailTerm * 0.4
        return min(1.0, raw * TraceTurnView.harshGain)
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        guard stroke.count >= 3 else { return }   // nothing traced → host records no answer
        SoundPlayer.shared.play(.lockin)
        session.submitTrace(errorPerMille: Int((meanError() * 1000).rounded()), for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submit()
    }

    // MARK: - Simplify

    /// Simplify fattens the line into a tolerance band: any part of your
    /// trace within `scoreTolerance` of the line (a canvas fraction) counts
    /// as dead-on. The band is drawn at exactly this width, so what you see
    /// is what forgives you. Entirely on your own phone.
    private var scoreTolerance: Double {
        switch session.myAssist {
        case .little: return 0.022
        case .big: return 0.045
        case .cheating: return 0.075
        default: return 0.0
        }
    }

    /// The painted guide width in points — the base line stays thin; an
    /// assisted band is drawn at twice the tolerance so it matches the zone
    /// that actually scores.
    private func guideWidth(side: Double) -> Double {
        max(6, scoreTolerance * 2 * side)
    }

    /// A smooth winding line through seeded control points (Catmull-Rom),
    /// sampled to a polyline in canvas fractions.
    static func line(seed: UInt64) -> [CGPoint] {
        var generator = SeededGenerator(seed: seed)
        var ctrl: [CGPoint] = []
        for _ in 0..<5 {
            ctrl.append(CGPoint(
                x: Double.random(in: 0.14...0.86, using: &generator),
                y: Double.random(in: 0.16...0.84, using: &generator)
            ))
        }
        let padded = [ctrl.first!] + ctrl + [ctrl.last!]
        var samples: [CGPoint] = []
        for i in 1..<(padded.count - 2) {
            let p0 = padded[i - 1], p1 = padded[i], p2 = padded[i + 1], p3 = padded[i + 2]
            for s in 0..<14 {
                let t = Double(s) / 14
                samples.append(catmullRom(p0, p1, p2, p3, t))
            }
        }
        samples.append(ctrl.last!)
        return samples.map { CGPoint(x: min(0.96, max(0.04, $0.x)), y: min(0.96, max(0.04, $0.y))) }
    }

    private static func catmullRom(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: Double) -> CGPoint {
        let t2 = t * t
        let t3 = t2 * t
        func axis(_ a0: Double, _ a1: Double, _ a2: Double, _ a3: Double) -> Double {
            let c0 = 2 * a1
            let c1 = (-a0 + a2) * t
            let c2 = (2 * a0 - 5 * a1 + 4 * a2 - a3) * t2
            let c3 = (-a0 + 3 * a1 - 3 * a2 + a3) * t3
            return 0.5 * (c0 + c1 + c2 + c3)
        }
        let x = axis(Double(p0.x), Double(p1.x), Double(p2.x), Double(p3.x))
        let y = axis(Double(p0.y), Double(p1.y), Double(p2.y), Double(p3.y))
        return CGPoint(x: x, y: y)
    }
}

/// Closest trace to the line takes the point.
struct TraceRevealView: View {
    let session: GameSession
    let reveal: TraceReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody traced it…"
                : "✏️ \(session.names(reveal.winners)) traced it best!",
            rows: reveal.results
                .sorted { ($0.errorPerMille ?? .max) < ($1.errorPerMille ?? .max) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "✏️",
                              value: r.errorPerMille.map { "\($0 / 10)% off" }, empty: "no trace")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next line"
        )
    }
}
