import SwiftUI

/// Shared roundness scorer. Players submit their raw stroke and the HOST
/// runs this over it — scores are never client-claimed.
enum CircleScore {
    /// 0–100 from a flattened (x0,y0,x1,y1…) unit-square stroke, or nil
    /// if it isn't a plausible circle attempt.
    static func evaluate(flat: [Double]) -> Double? {
        guard flat.count >= 40, flat.count % 2 == 0 else { return nil }
        var points: [(x: Double, y: Double)] = []
        points.reserveCapacity(flat.count / 2)
        var index = 0
        while index < flat.count {
            points.append((flat[index], flat[index + 1]))
            index += 2
        }
        let cx = points.map(\.x).reduce(0, +) / Double(points.count)
        let cy = points.map(\.y).reduce(0, +) / Double(points.count)
        let radii = points.map { (($0.x - cx) * ($0.x - cx) + ($0.y - cy) * ($0.y - cy)).squareRoot() }
        let meanRadius = radii.reduce(0, +) / Double(radii.count)
        guard meanRadius > 0.05 else { return nil }

        // Wobble: how much the radius varies around its mean.
        let variance = radii.map { ($0 - meanRadius) * ($0 - meanRadius) }.reduce(0, +) / Double(radii.count)
        let wobble = variance.squareRoot() / meanRadius

        // Coverage: did the stroke actually go all the way around?
        var sweep = 0.0
        var previous = atan2(points[0].y - cy, points[0].x - cx)
        for point in points.dropFirst() {
            let angle = atan2(point.y - cy, point.x - cx)
            var delta = angle - previous
            while delta > .pi { delta -= 2 * .pi }
            while delta < -.pi { delta += 2 * .pi }
            sweep += delta
            previous = angle
        }
        let coverage = min(1.0, abs(sweep) / (2 * .pi))

        // Closure: the gap between where you started and finished.
        let last = points[points.count - 1]
        let gap = ((points[0].x - last.x) * (points[0].x - last.x)
                 + (points[0].y - last.y) * (points[0].y - last.y)).squareRoot()
        let closure = gap / (2 * .pi * meanRadius)

        var score = 100.0
        score -= wobble * 300
        score -= max(0, 0.95 - coverage) * 300
        score -= min(closure, 0.3) * 100
        return max(0, min(100, (score * 10).rounded() / 10))
    }
}

/// One Perfect Circle turn: one finger, one stroke, ten seconds. Lifting
/// your finger locks it in; your score stays hidden until the reveal.
struct CircleTurnView: View {
    let session: GameSession
    let turn: CircleTurn

    @State private var strokePoints: [CGPoint] = []
    @State private var submitted = false

    private let canvasSize: CGFloat = 300

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let remaining = max(0, turn.deadline.timeIntervalSince(now))
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text(header(now: now))
                    .font(Theme.display(24))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                drawingCanvas(now: now)
                if !submitted && now >= turn.startAt && now < turn.deadline {
                    Text("\(Int(remaining.rounded(.up)))s — lifting your finger locks it in")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private func header(now: Date) -> String {
        if submitted { return "Locked in — scores at the reveal!" }
        if now < turn.startAt { return "Get ready…" }
        if now >= turn.deadline { return "Time's up!" }
        return "Draw a perfect circle"
    }

    private func drawingCanvas(now: Date) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface)
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
            if let assist = session.myAssist, !submitted {
                // Simplify: a guide ring to trace — faint and dashed at
                // level 1, bolder from level 2 (level 3 also gets a score
                // bump from the host).
                Circle()
                    .stroke(
                        Theme.cyan.opacity(assist == .little ? 0.18 : 0.32),
                        style: StrokeStyle(
                            lineWidth: assist >= .big ? 10 : 5,
                            dash: assist == .little ? [6, 9] : []
                        )
                    )
                    .frame(width: canvasSize * 0.68, height: canvasSize * 0.68)
            }
            if !strokePoints.isEmpty {
                Path { path in
                    path.move(to: strokePoints[0])
                    for point in strokePoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(
                    session.color(session.mySlot),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .frame(width: canvasSize, height: canvasSize)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !submitted,
                          Date() >= turn.startAt,
                          Date() < turn.deadline else { return }
                    let point = CGPoint(
                        x: min(max(0, value.location.x), canvasSize),
                        y: min(max(0, value.location.y), canvasSize)
                    )
                    strokePoints.append(point)
                }
                .onEnded { _ in
                    finishStroke()
                }
        )
    }

    private func finishStroke() {
        guard !submitted else { return }
        // Accidental taps clear and let you try again; a real stroke locks.
        guard strokePoints.count >= 20 else {
            strokePoints = []
            return
        }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        // Downsample to keep the payload small, normalize to unit square.
        let stride = max(1, strokePoints.count / 120)
        var flat: [Double] = []
        var index = 0
        while index < strokePoints.count {
            flat.append(Double(strokePoints[index].x / canvasSize))
            flat.append(Double(strokePoints[index].y / canvasSize))
            index += stride
        }
        session.submitCircle(path: flat, for: turn)
    }
}

/// Everyone's actual circles side by side, scored.
struct CircleRevealView: View {
    let session: GameSession
    let reveal: CircleReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text(headline)
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            drawingsGrid
            footer
            Spacer()
        }
        .padding(.top, 8)
    }

    private var headline: String {
        if reveal.winners.isEmpty {
            return "Nobody drew a circle…"
        }
        return "⭕ \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "draws" : "draw") the roundest!"
    }

    private var sortedResults: [CircleResult] {
        reveal.results.sorted { ($0.score ?? -1) > ($1.score ?? -1) }
    }

    private var drawingsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            ForEach(sortedResults) { result in
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.surface)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                reveal.winners.contains(result.slot) ? Theme.cyan : Theme.hairline,
                                lineWidth: reveal.winners.contains(result.slot) ? 2 : 1
                            )
                        if let path = result.path {
                            StrokeThumb(flat: path, color: session.color(result.slot))
                                .padding(8)
                        } else {
                            Text("—")
                                .font(Theme.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(session.color(result.slot))
                            .frame(width: 8, height: 8)
                        Text(session.name(result.slot))
                            .font(Theme.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(result.score.map { String(format: "%.1f", $0) } ?? "0")
                            .font(Theme.caption.weight(.bold))
                            .monospacedDigit()
                    }
                }
            }
        }
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
                    Text("Next circle in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}

/// Renders a flattened unit-square stroke into whatever space it's given.
struct StrokeThumb: View {
    let flat: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            Path { path in
                guard flat.count >= 4 else { return }
                path.move(to: CGPoint(x: flat[0] * size, y: flat[1] * size))
                var index = 2
                while index + 1 < flat.count {
                    path.addLine(to: CGPoint(x: flat[index] * size, y: flat[index + 1] * size))
                    index += 2
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
    }
}
