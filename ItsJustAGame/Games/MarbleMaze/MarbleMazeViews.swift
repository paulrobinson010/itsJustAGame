import SwiftUI

/// A perfect maze on a size×size grid, generated deterministically from a
/// seed (recursive backtracker) so every device draws the identical one.
/// Cell coordinates are 1 unit each; the maze lives in [0,size]×[0,size].
struct MazeModel {
    let size: Int
    /// Wall line segments (ax, ay, bx, by) in cell units: the outer border
    /// plus every closed passage between adjacent cells. Computed once.
    let segments: [(Double, Double, Double, Double)]
    /// Centres of the cells on the (unique) path from start to exit — the
    /// Simplify hint line.
    let solutionPath: [(Double, Double)]

    var start: (Double, Double) { (0.5, 0.5) }
    var exit: (Double, Double) { (Double(size) - 0.5, Double(size) - 0.5) }

    init(seed: UInt64, size: Int) {
        self.size = size
        var right = Array(repeating: Array(repeating: false, count: size), count: size)
        var down = Array(repeating: Array(repeating: false, count: size), count: size)
        var visited = Array(repeating: Array(repeating: false, count: size), count: size)
        var generator = SeededGenerator(seed: seed)
        var stack: [(Int, Int)] = [(0, 0)]
        visited[0][0] = true
        while let (c, r) = stack.last {
            var options: [(Int, Int, Int)] = []  // (nc, nr, direction)
            if c + 1 < size, !visited[c + 1][r] { options.append((c + 1, r, 0)) }  // right
            if c - 1 >= 0, !visited[c - 1][r] { options.append((c - 1, r, 1)) }    // left
            if r + 1 < size, !visited[c][r + 1] { options.append((c, r + 1, 2)) }  // down
            if r - 1 >= 0, !visited[c][r - 1] { options.append((c, r - 1, 3)) }    // up
            guard !options.isEmpty else { stack.removeLast(); continue }
            let (nc, nr, dir) = options[Int.random(in: 0..<options.count, using: &generator)]
            switch dir {
            case 0: right[c][r] = true
            case 1: right[nc][nr] = true
            case 2: down[c][r] = true
            default: down[nc][nr] = true
            }
            visited[nc][nr] = true
            stack.append((nc, nr))
        }

        // Wall segments.
        var segs: [(Double, Double, Double, Double)] = []
        let s = Double(size)
        segs.append((0, 0, s, 0))
        segs.append((0, s, s, s))
        segs.append((0, 0, 0, s))
        segs.append((s, 0, s, s))
        for c in 0..<size {
            for r in 0..<size {
                if c + 1 < size, !right[c][r] {
                    let x = Double(c + 1)
                    segs.append((x, Double(r), x, Double(r + 1)))
                }
                if r + 1 < size, !down[c][r] {
                    let y = Double(r + 1)
                    segs.append((Double(c), y, Double(c + 1), y))
                }
            }
        }
        self.segments = segs

        // Solution path (BFS over open passages).
        var prev = Array(repeating: Array(repeating: (-1, -1), count: size), count: size)
        var seen = Array(repeating: Array(repeating: false, count: size), count: size)
        var queue: [(Int, Int)] = [(0, 0)]
        seen[0][0] = true
        var head = 0
        while head < queue.count {
            let (c, r) = queue[head]; head += 1
            if c == size - 1, r == size - 1 { break }
            var nbrs: [(Int, Int)] = []
            if c + 1 < size, right[c][r] { nbrs.append((c + 1, r)) }
            if c - 1 >= 0, right[c - 1][r] { nbrs.append((c - 1, r)) }
            if r + 1 < size, down[c][r] { nbrs.append((c, r + 1)) }
            if r - 1 >= 0, down[c][r - 1] { nbrs.append((c, r - 1)) }
            for (nc, nr) in nbrs where !seen[nc][nr] {
                seen[nc][nr] = true
                prev[nc][nr] = (c, r)
                queue.append((nc, nr))
            }
        }
        var path: [(Double, Double)] = []
        var cur = (size - 1, size - 1)
        while cur.0 >= 0 {
            path.append((Double(cur.0) + 0.5, Double(cur.1) + 0.5))
            if cur == (0, 0) { break }
            cur = prev[cur.0][cur.1]
        }
        self.solutionPath = path.reversed()
    }
}

/// One Marble Maze turn: tilt to roll the ball from the top-left to the
/// exit at the bottom-right. Time runs locally from the shared start.
struct MazeTurnView: View {
    let session: GameSession
    let turn: MazeTurn

    @State private var ballX = 0.5
    @State private var ballY = 0.5
    @State private var velX = 0.0
    @State private var velY = 0.0
    @State private var resultMs: Int?
    @State private var submitted = false

    private let maze: MazeModel
    private let radius = 0.30

    private var motion: MotionService { MotionService.shared }

    init(session: GameSession, turn: MazeTurn) {
        self.session = session
        self.turn = turn
        self.maze = MazeModel(seed: turn.seed, size: turn.size)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · roll to the exit")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now)
                board
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedMaze(for: turn)
            if submitted { resultMs = 0; return }
            motion.start()
            await run()
        }
        .onDisappear { motion.stop() }
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        if let resultMs, resultMs > 0 {
            Text("Escaped in \(timeString(resultMs))! — waiting…")
                .font(Theme.display(20))
                .multilineTextAlignment(.center)
        } else if submitted {
            Text("Waiting…").font(Theme.display(22))
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if !motion.isAvailable {
            Text("This game needs a real device")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.magenta)
        } else if now >= turn.deadline {
            Text("Time's up — waiting for the reveal…").font(Theme.headline)
        } else {
            let elapsed = Int(now.timeIntervalSince(turn.startAt) * 1000)
            Text(timeString(max(0, elapsed)))
                .font(Theme.display(24))
                .monospacedDigit()
        }
    }

    private var board: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let cell = side / Double(turn.size)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: side, height: side)

                // Simplify: draw the solution path.
                if let lineOpacity = pathOpacity {
                    Path { p in
                        let pts = maze.solutionPath
                        guard let first = pts.first else { return }
                        p.move(to: CGPoint(x: first.0 * cell, y: first.1 * cell))
                        for pt in pts.dropFirst() {
                            p.addLine(to: CGPoint(x: pt.0 * cell, y: pt.1 * cell))
                        }
                    }
                    .stroke(Theme.cyan.opacity(lineOpacity), style: StrokeStyle(lineWidth: cell * 0.14, lineCap: .round, lineJoin: .round))
                    .frame(width: side, height: side)
                }

                // Walls.
                Path { p in
                    for seg in maze.segments {
                        p.move(to: CGPoint(x: seg.0 * cell, y: seg.1 * cell))
                        p.addLine(to: CGPoint(x: seg.2 * cell, y: seg.3 * cell))
                    }
                }
                .stroke(Theme.ink.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: side, height: side)

                // Exit flag.
                Text("🏁")
                    .font(.system(size: cell * 0.6))
                    .position(x: maze.exit.0 * cell, y: maze.exit.1 * cell)

                // The ball.
                Circle()
                    .fill(session.color(session.mySlot))
                    .frame(width: cell * radius * 2, height: cell * radius * 2)
                    .shadow(color: session.color(session.mySlot).opacity(0.6), radius: 4)
                    .position(x: ballX * cell, y: ballY * cell)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 24)
    }

    // MARK: - Simplify

    private var pathOpacity: Double? {
        switch session.myAssist {
        case .big: return 0.35
        case .cheating: return 0.7
        default: return nil
        }
    }

    private var gentle: Bool {
        session.myAssist == .little || session.myAssist == .cheating
    }

    // MARK: - Physics

    private func run() async {
        while Date() < turn.startAt && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.02)) }
        var last = Date()
        while !Task.isCancelled, !submitted {
            try? await Task.sleep(for: .seconds(1.0 / 60.0))
            let now = Date()
            let dt = min(now.timeIntervalSince(last), 0.05)
            last = now
            if now >= turn.deadline { break }
            step(dt: dt)
            let dx = ballX - maze.exit.0
            let dy = ballY - maze.exit.1
            if (dx * dx + dy * dy).squareRoot() < 0.32 {
                finish(elapsed: Int(now.timeIntervalSince(turn.startAt) * 1000))
                break
            }
        }
    }

    private func step(dt: Double) {
        let control = gentle ? 0.72 : 1.0
        let accel = 14.0 * control
        let ax = min(max(motion.rollDegrees / 32, -1), 1) * accel
        let ay = min(max(motion.pitchDegrees / 32, -1), 1) * accel
        velX += ax * dt
        velY += ay * dt
        // Lighter damping so the ball keeps its roll (still enough to stay
        // controllable).
        let damp = pow(0.03, dt)
        velX *= damp
        velY *= damp
        // Speed clamp.
        let speed = (velX * velX + velY * velY).squareRoot()
        let maxSpeed = gentle ? 9.0 : 12.0
        if speed > maxSpeed {
            velX *= maxSpeed / speed
            velY *= maxSpeed / speed
        }
        ballX += velX * dt
        ballY += velY * dt
        resolveCollisions()
    }

    /// Push the ball out of any wall it overlaps and cancel the velocity
    /// component driving it into the wall.
    private func resolveCollisions() {
        for seg in maze.segments {
            let ex = seg.2 - seg.0
            let ey = seg.3 - seg.1
            let len2 = ex * ex + ey * ey
            guard len2 > 0 else { continue }
            let t = min(max(((ballX - seg.0) * ex + (ballY - seg.1) * ey) / len2, 0), 1)
            let cx = seg.0 + ex * t
            let cy = seg.1 + ey * t
            let dx = ballX - cx
            let dy = ballY - cy
            let d2 = dx * dx + dy * dy
            if d2 < radius * radius {
                let d = d2.squareRoot()
                let nx: Double, ny: Double
                if d > 1e-6 { nx = dx / d; ny = dy / d } else { nx = 0; ny = -1 }
                ballX += nx * (radius - d)
                ballY += ny * (radius - d)
                let vdot = velX * nx + velY * ny
                if vdot < 0 { velX -= vdot * nx; velY -= vdot * ny }
            }
        }
    }

    private func finish(elapsed: Int) {
        guard !submitted else { return }
        resultMs = elapsed
        submitted = true
        SoundPlayer.shared.play(.point)
        session.submitMaze(elapsedMs: elapsed, for: turn)
    }

    private func timeString(_ ms: Int) -> String {
        String(format: "%.1fs", Double(ms) / 1000)
    }
}

/// Fastest escape takes the point.
struct MazeRevealView: View {
    let session: GameSession
    let reveal: MazeReveal

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
            return "Nobody found the exit…"
        }
        return "🏁 \(session.names(reveal.winners)) escaped first!"
    }

    private var sortedResults: [MazeResult] {
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
                        Text("🏁")
                    }
                    Spacer()
                    if let elapsedMs = result.elapsedMs {
                        Text(String(format: "%.1fs", Double(elapsedMs) / 1000))
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("didn't escape")
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
                    Text("Next maze in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
