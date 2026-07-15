import SwiftUI

/// One Odd One Out turn: a 5×5 grid where every colour appears as a pair,
/// except one that appears alone — tap the unpaired one. The colours (which
/// twelve pairs, which loner, and where everything lands) are built
/// identically on every device from the seed. Wrong taps cost time, and the
/// find is timed locally, so latency never matters.
struct OddTurnView: View {
    let session: GameSession
    let turn: OddTurn

    @State private var appearedAt: Date?
    @State private var submitted = false
    @State private var penaltyMs = 0
    @State private var wrongFlash: Int?
    @State private var found = false

    /// The colour of each tile, and the index of the one with no pair.
    private let cellColors: [Color]
    private let oddIndex: Int

    init(session: GameSession, turn: OddTurn) {
        self.session = session
        self.turn = turn
        var generator = SeededGenerator(seed: turn.seed)
        let cells = turn.gridSize * turn.gridSize
        let pairs = (cells - 1) / 2                       // 12 for a 5×5

        // Pick (pairs + 1) clearly-distinct colours: one loner + the pairs.
        let chosen = Array(OddTurnView.palette.shuffled(using: &generator).prefix(pairs + 1))
        // Tokens into `chosen`: 0 = the loner (once), 1…pairs twice each.
        var tokens = [0]
        for i in 1...pairs { tokens.append(i); tokens.append(i) }
        tokens.shuffle(using: &generator)

        self.cellColors = tokens.map { chosen[$0] }
        self.oddIndex = tokens.firstIndex(of: 0) ?? 0
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let playing = appearedAt != nil && !submitted && now < turn.deadline
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · find the loner")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.3)
                header(now: now, playing: playing)
                grid(playing: playing)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedOdd(for: turn)
            if submitted { return }
            let wait = turn.startAt.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            appearedAt = Date()
            await autoSubmit()
        }
    }

    @ViewBuilder
    private func header(now: Date, playing: Bool) -> some View {
        if found {
            Text("Got it! — waiting…").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else if submitted {
            Text("Time's up — waiting…").font(Theme.headline)
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("Which has no pair? · \(remaining)s").font(Theme.display(22)).foregroundStyle(Theme.magenta)
        }
    }

    private func grid(playing: Bool) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let n = turn.gridSize
            let gap = side * 0.02
            let cell = (side - gap * Double(n - 1)) / Double(n)
            VStack(spacing: gap) {
                ForEach(0..<n, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<n, id: \.self) { col in
                            let i = row * n + col
                            RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                                .fill(colour(at: i))
                                .frame(width: cell, height: cell)
                                .overlay(
                                    RoundedRectangle(cornerRadius: cell * 0.22, style: .continuous)
                                        .stroke(strokeColor(for: i), lineWidth: strokeWidth(for: i))
                                )
                                .onTapGesture { tap(i) }
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .allowsHitTesting(playing)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 20)
    }

    private func colour(at i: Int) -> Color {
        i < cellColors.count ? cellColors[i] : .gray
    }

    private func strokeColor(for i: Int) -> Color {
        if wrongFlash == i { return .white }
        if oddRingWidth > 0 && i == oddIndex { return .white }
        return .clear
    }

    private func strokeWidth(for i: Int) -> Double {
        if wrongFlash == i { return 4 }
        if i == oddIndex { return oddRingWidth }
        return 0
    }

    // MARK: - Tapping

    private func tap(_ i: Int) {
        guard let start = appearedAt, !submitted, !found else { return }
        if i == oddIndex {
            found = true
            submitted = true
            let elapsed = Int(max(0, Date().timeIntervalSince(start)) * 1000) + penaltyMs
            SoundPlayer.shared.play(.point)
            session.submitOdd(timeMs: elapsed, for: turn)
        } else {
            penaltyMs += GameTiming.oddWrongPenaltyMs
            wrongFlash = i
            SoundPlayer.shared.play(.lose)
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                if wrongFlash == i { wrongFlash = nil }
            }
        }
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        // Ran out of time — stop; the host records "never found" for us.
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
    }

    // MARK: - Simplify

    /// A ring on the loner — a faint hint at level 1, growing to a bold
    /// outline at level 3. Invisible to everyone else.
    private var oddRingWidth: Double {
        switch session.myAssist {
        case .cheating: return 4
        case .big: return 2.5
        case .little: return 1.5
        default: return 0
        }
    }

    /// Twelve-plus clearly-distinct colours — all bright enough to read on
    /// the dark board and far enough apart that a pair is never in doubt.
    static let palette: [Color] = [
        Color(red: 0.92, green: 0.24, blue: 0.24),   // red
        Color(red: 0.98, green: 0.56, blue: 0.13),   // orange
        Color(red: 0.98, green: 0.85, blue: 0.24),   // yellow
        Color(red: 0.66, green: 0.84, blue: 0.22),   // lime
        Color(red: 0.29, green: 0.75, blue: 0.34),   // green
        Color(red: 0.13, green: 0.72, blue: 0.60),   // teal
        Color(red: 0.20, green: 0.78, blue: 0.90),   // cyan
        Color(red: 0.26, green: 0.53, blue: 0.96),   // blue
        Color(red: 0.40, green: 0.36, blue: 0.86),   // indigo
        Color(red: 0.62, green: 0.36, blue: 0.90),   // purple
        Color(red: 0.90, green: 0.32, blue: 0.80),   // magenta
        Color(red: 0.98, green: 0.52, blue: 0.66),   // pink
        Color(red: 0.62, green: 0.44, blue: 0.28),   // brown
        Color(red: 0.80, green: 0.80, blue: 0.84),   // silver
        Color(red: 0.55, green: 0.78, blue: 0.98),   // sky
        Color(red: 0.96, green: 0.74, blue: 0.52),   // sand
    ]
}

/// Fastest to find the loner takes the point.
struct OddRevealView: View {
    let session: GameSession
    let reveal: OddReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody spotted it…"
                : "👁️ \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") quickest!",
            rows: reveal.results
                .sorted { ($0.timeMs ?? .max) < ($1.timeMs ?? .max) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "👁️",
                              value: r.timeMs.map { String(format: "%.1fs", Double($0) / 1000) },
                              empty: "missed")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next grid"
        )
    }
}
