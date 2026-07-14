import SwiftUI

/// One Spirit Level turn: tilt the phone (roll) to slide the bubble onto
/// the target mark, then lock it in — no numbers, just your eye. Angular
/// error is measured locally, hidden until the reveal.
struct LevelTurnView: View {
    let session: GameSession
    let turn: LevelTurn

    @State private var submitted = false
    @State private var lockedError: Double?
    /// Device-local "GO" moment, so the run-up is timed on this phone.
    @State private var goAt: Date?

    private var motion: MotionService { MotionService.shared }

    private var playEndsAt: Date? {
        goAt?.addingTimeInterval(GameTiming.levelHoldSeconds)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let now = context.date
            let roll = motion.rollDegrees
            let live = leveling(now: now)
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · line up the bubble")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now, roll: roll)
                Spacer(minLength: 8)
                gauge(roll: roll)
                if session.myAssist == .cheating, live {
                    Text(String(format: "%.1f° off", abs(roll - turn.targetDegrees)))
                        .font(Theme.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.cyan)
                }
                Spacer(minLength: 8)
                if live {
                    Button {
                        lockIn(roll: roll)
                    } label: {
                        Label("Lock it in", systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedLevel(for: turn)
            motion.start()
            goAt = Date().addingTimeInterval(GameTiming.tiltCountdownSeconds)
            await autoLock()
        }
        .onDisappear { motion.stop() }
    }

    /// Whether the bubble is live to tilt and lock right now.
    private func leveling(now: Date) -> Bool {
        guard let go = goAt, let end = playEndsAt, !submitted else { return false }
        return now >= go && now < end
    }

    @ViewBuilder
    private func header(now: Date, roll: Double) -> some View {
        if submitted {
            Text("Locked in — waiting…")
                .font(Theme.display(22))
        } else if !motion.isAvailable {
            Text("This game needs a real device")
                .font(Theme.subheadline)
                .foregroundStyle(Theme.magenta)
        } else if let go = goAt, now < go {
            let count = Int(go.timeIntervalSince(now).rounded(.up))
            Text(count > 0 ? "\(count)" : "GO!")
                .font(Theme.display(count > 0 ? 64 : 40))
                .foregroundStyle(Theme.magenta)
                .contentTransition(.numericText())
        } else if let end = playEndsAt, now >= end {
            Text("Time's up — waiting for the reveal…")
                .font(Theme.headline)
        } else if let end = playEndsAt {
            let remaining = Int(max(0, end.timeIntervalSince(now)).rounded(.up))
            Text("Tilt to the mark · \(remaining)s")
                .font(Theme.display(22))
        } else {
            Text("Get ready…")
                .font(Theme.display(24))
        }
    }

    private func gauge(roll: Double) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let targetX = position(turn.targetDegrees) * w
            let bubbleX = position(roll) * w
            let inZone = abs(roll - turn.targetDegrees) <= toleranceDegrees
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surface)
                    .frame(height: 56)
                    .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                // Simplify tolerance band.
                if let band = bandDegrees {
                    let bandW = (band * 2 / 90) * w
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.cyan.opacity(0.16))
                        .frame(width: bandW, height: 52)
                        .position(x: targetX, y: h / 2)
                }
                // Target mark.
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.magenta)
                    .frame(width: 3, height: 64)
                    .position(x: targetX, y: h / 2)
                // The bubble.
                Circle()
                    .fill(bubbleShowsGood && inZone ? Color.green : Theme.cyan)
                    .frame(width: 40, height: 40)
                    .shadow(color: (bubbleShowsGood && inZone ? Color.green : Theme.cyan).opacity(0.6), radius: 8)
                    .position(x: min(max(bubbleX, 20), w - 20), y: h / 2)
            }
            .frame(height: h)
        }
        .frame(height: 90)
        .padding(.horizontal, 24)
    }

    // MARK: - Simplify

    /// Degrees each side of the target the highlight band spans (nil = off).
    private var bandDegrees: Double? {
        switch session.myAssist {
        case .little: return 10
        case .big: return 5
        default: return nil
        }
    }

    /// Whether the bubble turns green when close (levels 2–3).
    private var bubbleShowsGood: Bool {
        session.myAssist == .big || session.myAssist == .cheating
    }

    private var toleranceDegrees: Double { 4 }

    private func position(_ deg: Double) -> Double {
        min(max((deg + 45) / 90, 0), 1)
    }

    private func lockIn(roll: Double) {
        guard !submitted else { return }
        let error = abs(roll - turn.targetDegrees)
        lockedError = error
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitLevel(errorMilliDeg: Int(error * 1000), for: turn)
    }

    private func autoLock() async {
        let end = playEndsAt ?? Date().addingTimeInterval(GameTiming.tiltCountdownSeconds + GameTiming.levelHoldSeconds)
        let interval = end.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        lockIn(roll: motion.rollDegrees)
    }
}

/// Closest to the mark takes the point.
struct LevelRevealView: View {
    let session: GameSession
    let reveal: LevelReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text("Target: \(Int(reveal.targetDegrees))°")
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
            return "Nobody locked one in…"
        }
        return "🫧 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!"
    }

    private var sortedResults: [LevelResult] {
        reveal.results.sorted { ($0.errorMilliDeg ?? .max) < ($1.errorMilliDeg ?? .max) }
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
                        Text("🫧")
                    }
                    Spacer()
                    if let error = result.errorMilliDeg {
                        Text(String(format: "%.1f° off", Double(error) / 1000))
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("no lock")
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
                    Text("Next mark in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
