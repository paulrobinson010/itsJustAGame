import SwiftUI

/// One Odd One Out turn: a grid of identical shapes with a single off-colour
/// cell (built identically everywhere from the seed; the gap shrinks as the
/// turn climbs). Tap it as fast as you can — wrong taps cost time. The find
/// is timed locally from when the grid appears, so latency never matters.
struct OddTurnView: View {
    let session: GameSession
    let turn: OddTurn

    @State private var appearedAt: Date?
    @State private var submitted = false
    @State private var penaltyMs = 0
    @State private var wrongFlash: Int?
    @State private var found = false

    private let oddIndex: Int
    private let baseHue: Double
    /// Base brightness gap for this turn before Simplify widens it.
    private let baseGap: Double

    init(session: GameSession, turn: OddTurn) {
        self.session = session
        self.turn = turn
        var generator = SeededGenerator(seed: turn.seed)
        self.oddIndex = Int.random(in: 0..<(turn.gridSize * turn.gridSize), using: &generator)
        self.baseHue = Double.random(in: 0...1, using: &generator)
        self.baseGap = max(0.06, 0.30 - Double(turn.turn - 1) * 0.035)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let playing = appearedAt != nil && !submitted && now < turn.deadline
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · spot the odd one")
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
            Text("Find it! · \(remaining)s").font(Theme.display(24)).foregroundStyle(Theme.magenta)
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
                                .fill(i == oddIndex ? oddColor : baseColor)
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

    private func strokeColor(for i: Int) -> Color {
        if wrongFlash == i { return Theme.magenta }
        if oddRingWidth > 0 && i == oddIndex {
            return session.myAssist == .cheating ? .white : .white.opacity(0.5)
        }
        return .clear
    }

    private func strokeWidth(for i: Int) -> Double {
        if wrongFlash == i { return 3 }
        if i == oddIndex { return oddRingWidth }
        return 0
    }

    // MARK: - Colours

    private var effectiveGap: Double { min(0.62, baseGap + assistBonus) }
    private var baseColor: Color { Color(hue: baseHue, saturation: 0.62, brightness: 0.8) }
    private var oddColor: Color { Color(hue: baseHue, saturation: 0.62, brightness: max(0.14, 0.8 - effectiveGap)) }

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

    /// Widens the colour gap locally, so the odd one pops more on the
    /// assisted phone — invisible to everyone else.
    private var assistBonus: Double {
        switch session.myAssist {
        case .little: return 0.12
        case .big: return 0.22
        case .cheating: return 0.34
        default: return 0
        }
    }

    /// A ring drawn on the odd cell — a hint at level 2, a bold outline at
    /// level 3, off otherwise.
    private var oddRingWidth: Double {
        switch session.myAssist {
        case .cheating: return 3
        case .big: return 2
        default: return 0
        }
    }
}

/// Fastest to find the odd one takes the point.
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
