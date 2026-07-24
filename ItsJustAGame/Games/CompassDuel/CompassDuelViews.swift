import SwiftUI

/// One Compass Duel turn: a seeded run of compass headings — physically
/// spin to face each one and hold it steady to lock it in. The device
/// times the whole run; fastest through them all wins, and if nobody
/// finishes, furthest through takes it. Timed locally, so latency never
/// matters — but everyone chases the identical headings.
struct CompassTurnView: View {
    let session: GameSession
    let turn: CompassTurn

    @State private var submitted = false
    @State private var locked = 0
    /// When the needle entered the cone; nil = currently outside.
    @State private var coneEnteredAt: Date?
    @State private var finishedAt: Date?

    /// The headings to face, degrees clockwise from north.
    private let targets: [Double]

    init(session: GameSession, turn: CompassTurn) {
        self.session = session
        self.turn = turn
        self.targets = CompassTurnView.headings(seed: turn.seed, count: turn.headingCount)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            let live = isLive(now: now)
            let heading = LocationService.shared.heading
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · face the heading")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now, live: live, heading: heading)
                if heading == nil {
                    Spacer()
                    VStack(spacing: 10) {
                        Image(systemName: "safari")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("No compass on this device")
                            .font(Theme.headline)
                        Text("Compass Duel needs a real iPhone — sit this one out.")
                            .font(Theme.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    Spacer()
                } else if let heading, live, locked < targets.count {
                    Spacer(minLength: 8)
                    dial(heading: heading, target: targets[locked], now: now)
                    Spacer(minLength: 8)
                } else {
                    Spacer()
                }
                progress
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .onChange(of: context.date) { _, newDate in
                advance(now: newDate)
            }
        }
        .task {
            submitted = session.hasSubmittedCompass(for: turn)
            LocationService.shared.startHeadingUpdates()
            if submitted { return }
            await autoFinish()
        }
        .onDisappear { LocationService.shared.stopHeadingUpdates() }
    }

    @ViewBuilder
    private func header(now: Date, live: Bool, heading: Double?) -> some View {
        if submitted, finishedAt != nil {
            Text("Done! — waiting…").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else if submitted {
            Text("\(locked) of \(targets.count) — waiting…").font(Theme.display(22))
        } else if now < turn.startAt {
            Text("On your feet…").font(Theme.display(24))
        } else if live, heading != nil, locked < targets.count {
            Text("Face \(compassName(targets[locked])) \(arrowGlyph(targets[locked]))")
                .font(Theme.display(28)).foregroundStyle(Theme.cyan)
        } else if live {
            Text("Spin to it!").font(Theme.display(24))
        } else {
            Text("Time! — waiting…").font(Theme.headline)
        }
    }

    /// A compass rose that stays fixed to the world (rotating against your
    /// heading) with the target wedge painted on. Point the top marker at
    /// the wedge and hold it.
    private func dial(heading: Double, target: Double, now: Date) -> some View {
        let relative = angleDelta(from: heading, to: target)
        let inCone = abs(relative) <= coneDegrees
        let holdFraction: Double = {
            guard inCone, let entered = coneEnteredAt else { return 0 }
            return min(1, now.timeIntervalSince(entered) / GameTiming.compassLockSeconds)
        }()
        return ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 2)
            // The world's north, spun so the rose stays put as you turn.
            ForEach([0, 90, 180, 270], id: \.self) { degree in
                Text(compassName(Double(degree)))
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .offset(y: -104)
                    .rotationEffect(.degrees(Double(degree) - heading))
            }
            // The target wedge, spanning the full ±cone.
            Circle()
                .trim(from: 0.5 - coneDegrees / 360, to: 0.5 + coneDegrees / 360)
                .stroke(inCone ? Color.green : Theme.magenta, style: StrokeStyle(lineWidth: 14, lineCap: .butt))
                .rotationEffect(.degrees(relative + 90))
            // You: the fixed needle at the top.
            Image(systemName: "location.north.fill")
                .font(.system(size: 30))
                .foregroundStyle(inCone ? Color.green : Theme.cyan)
                .offset(y: -70)
            // Hold-to-lock ring in the middle.
            Circle()
                .trim(from: 0, to: holdFraction)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 70, height: 70)
                .rotationEffect(.degrees(-90))
            Text(inCone ? "hold…" : "\(Int(abs(relative)))°")
                .font(Theme.headline)
                .monospacedDigit()
        }
        .frame(width: 230, height: 230)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(0..<targets.count, id: \.self) { index in
                Circle()
                    .fill(index < locked ? Color.green : Theme.surface)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    .frame(width: 14, height: 14)
            }
        }
    }

    private func isLive(now: Date) -> Bool {
        !submitted && now >= turn.startAt && now < turn.deadline
    }

    private func advance(now: Date) {
        guard isLive(now: now), locked < targets.count,
              let heading = LocationService.shared.heading else { return }
        let inCone = abs(angleDelta(from: heading, to: targets[locked])) <= coneDegrees
        if inCone {
            if let entered = coneEnteredAt {
                if now.timeIntervalSince(entered) >= GameTiming.compassLockSeconds {
                    locked += 1
                    coneEnteredAt = nil
                    SoundPlayer.shared.play(.tick)
                    if locked == targets.count {
                        finishedAt = now
                        submitted = true
                        SoundPlayer.shared.play(.lockin)
                        let ms = Int(now.timeIntervalSince(turn.startAt) * 1000)
                        session.submitCompass(elapsedMs: ms, completed: locked, for: turn)
                    }
                }
            } else {
                coneEnteredAt = now
            }
        } else {
            coneEnteredAt = nil
        }
    }

    private func autoFinish() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitCompass(elapsedMs: nil, completed: locked, for: turn)
    }

    /// Signed shortest turn from `heading` to `target`, in -180…180.
    private func angleDelta(from heading: Double, to target: Double) -> Double {
        var delta = (target - heading).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func compassName(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return names[index]
    }

    private func arrowGlyph(_ degrees: Double) -> String {
        let arrows = ["⬆️", "↗️", "➡️", "↘️", "⬇️", "↙️", "⬅️", "↖️"]
        let index = Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return arrows[index]
    }

    /// The seeded heading run: each at least 70° from the one before, so
    /// every heading means actually turning.
    static func headings(seed: UInt64, count: Int) -> [Double] {
        var generator = SeededGenerator(seed: seed)
        var result: [Double] = []
        var previous: Double?
        for _ in 0..<count {
            var candidate = Double.random(in: 0..<360, using: &generator)
            if let last = previous {
                var tries = 0
                while abs(shortestDelta(from: last, to: candidate)) < 70 && tries < 20 {
                    candidate = Double.random(in: 0..<360, using: &generator)
                    tries += 1
                }
            }
            result.append(candidate)
            previous = candidate
        }
        return result
    }

    private static func shortestDelta(from a: Double, to b: Double) -> Double {
        var delta = (b - a).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    // MARK: - Simplify

    /// A wider acceptance cone. Invisible to everyone else.
    private var coneDegrees: Double {
        switch session.myAssist {
        case .little: return 18
        case .big: return 25
        case .cheating: return 35
        default: return GameTiming.compassConeDegrees
        }
    }
}

/// Fastest through every heading takes the point.
struct CompassRevealView: View {
    let session: GameSession
    let reveal: CompassReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty
                ? "Nobody found their bearings…"
                : "🧭 \(session.names(reveal.winners)) span the fastest!",
            rows: reveal.results
                .sorted { sortKey($0) < sortKey($1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🧭",
                              value: r.elapsedMs.map { String(format: "%.1fs", Double($0) / 1000) }
                                  ?? (r.completed > 0 ? "\(r.completed) headings" : nil),
                              empty: "sat it out")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next bearings"
        )
    }

    /// Finishers first by time; then by how far they got.
    private func sortKey(_ r: CompassResult) -> Int {
        if let ms = r.elapsedMs { return ms }
        return 10_000_000 - r.completed * 1000
    }
}
