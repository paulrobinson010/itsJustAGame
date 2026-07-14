import SwiftUI

/// One Pour It turn: tip the phone to either side to pour, level off to
/// stop, hit the target line without spilling. Fill is integrated locally
/// from the roll, so latency never matters.
struct PourTurnView: View {
    let session: GameSession
    let turn: PourTurn

    @State private var fill: Double = 0
    @State private var overflowed = false
    @State private var submitted = false
    /// Device-local "GO" moment: set when the view appears, so the run-up is
    /// timed on this phone rather than the host's clock.
    @State private var goAt: Date?
    /// The phone's resting roll captured at GO — pouring is measured relative
    /// to it, so you can hold the phone however feels natural and tip either
    /// way.
    @State private var referenceRoll: Double = 0

    private var motion: MotionService { MotionService.shared }

    /// Play ends this long after GO (device-local, well inside the host's
    /// collection window).
    private var playEndsAt: Date? {
        goAt?.addingTimeInterval(GameTiming.pourSeconds)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            let live = pouring(now: now)
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · pour to the line")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now)
                glass
                if showFillNumber, !submitted, live {
                    Text("\(Int(fill.rounded()))%")
                        .font(Theme.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.cyan)
                }
                if !submitted, live, !overflowed {
                    Button {
                        submit()
                    } label: {
                        Label("That's it — stop", systemImage: "hand.raised.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedPour(for: turn)
            if submitted { return }
            motion.start()
            // Let device motion warm up, then capture the resting pose so the
            // glass already responds to tilt during the countdown.
            try? await Task.sleep(for: .milliseconds(250))
            referenceRoll = motion.rollDegrees
            goAt = Date().addingTimeInterval(GameTiming.tiltCountdownSeconds)
            await pourLoop()
        }
        .onDisappear { motion.stop() }
    }

    /// Whether the phone is actively pouring right now.
    private func pouring(now: Date) -> Bool {
        guard let go = goAt, let end = playEndsAt, !submitted else { return false }
        return now >= go && now < end
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        if submitted {
            Text(overflowed ? "Spilled! — waiting…" : "Locked in at \(Int(fill.rounded()))% — waiting…")
                .font(Theme.display(20))
                .foregroundStyle(overflowed ? Theme.magenta : .white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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
        } else if let end = playEndsAt {
            let remaining = Int(max(0, end.timeIntervalSince(now)).rounded(.up))
            Text("Tilt to pour · \(remaining)s")
                .font(Theme.display(22))
        } else {
            Text("Get ready…")
                .font(Theme.display(24))
        }
    }

    private var glass: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let glassW = min(w * 0.5, 200)
            let glassH = h - 20
            let x = w / 2
            let bottom = 10 + glassH
            let liquidH = glassH * (fill / 100)
            let targetY = 10 + glassH * (1 - Double(turn.targetPercent) / 100)
            ZStack(alignment: .top) {
                // A plain glass that tips the same way you roll the phone —
                // either direction pours — live from the countdown on, so you
                // can find the feel before it counts.
                Text("🥛")
                    .font(.system(size: 40))
                    .rotationEffect(.degrees(submitted ? 0 : min(max(motion.rollDegrees - referenceRoll, -70), 70)))
                    .position(x: x, y: 6)

                // Glass outline.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 2)
                    .frame(width: glassW, height: glassH)
                    .position(x: x, y: 10 + glassH / 2)

                // Liquid.
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(overflowed ? Theme.magenta.opacity(0.85) : Theme.cyan.opacity(0.7))
                    .frame(width: glassW - 8, height: max(0, liquidH))
                    .position(x: x, y: bottom - liquidH / 2)

                // Simplify tolerance band around the line.
                if let band = bandPercent {
                    let bandH = glassH * (Double(band * 2) / 100)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.green.opacity(0.18))
                        .frame(width: glassW, height: bandH)
                        .position(x: x, y: targetY)
                }
                // Target line.
                Rectangle()
                    .fill(Theme.magenta)
                    .frame(width: glassW + 16, height: 3)
                    .position(x: x, y: targetY)
            }
            .frame(width: w, height: h)
        }
        .frame(height: 300)
        .padding(.horizontal, 24)
    }

    // MARK: - Simplify

    private var bandPercent: Int? {
        switch session.myAssist {
        case .little, .big: return 8
        default: return nil
        }
    }

    private var showFillNumber: Bool {
        session.myAssist == .big || session.myAssist == .cheating
    }

    // MARK: - Pour loop

    private func pourLoop() async {
        let go = goAt ?? Date()
        while Date() < go && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.02)) }
        // Capture the resting pose so pouring is a tilt from here, whatever
        // way the phone is being held.
        referenceRoll = motion.rollDegrees
        let end = playEndsAt ?? go.addingTimeInterval(GameTiming.pourSeconds)
        var last = Date()
        let slow = session.myAssist == .little || session.myAssist == .big
        let rateScale = slow ? 0.6 : 1.0
        while !Task.isCancelled, !submitted {
            try? await Task.sleep(for: .seconds(1.0 / 60.0))
            let now = Date()
            let dt = now.timeIntervalSince(last)
            last = now
            if now >= end {
                submit()
                break
            }
            // Tip the phone to either side from the resting pose to pour;
            // level back off to stop. Magnitude drives the flow, so it pours
            // whichever way you tilt.
            let tilt = abs(motion.rollDegrees - referenceRoll)
            let effective = min(max(tilt - 6, 0), 48)
            var next = fill + effective * 0.8 * rateScale * dt
            if session.myAssist == .cheating {
                // Top level: it simply won't overflow past the line.
                next = min(next, Double(turn.targetPercent))
            }
            if next >= 100 {
                fill = 100
                overflowed = true
                submit()
                break
            }
            fill = next
        }
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(overflowed ? .lose : .lockin)
        session.submitPour(fillPercent: Int(fill.rounded()), overflowed: overflowed, for: turn)
    }
}

/// Closest to the line (without spilling) takes the point.
struct PourRevealView: View {
    let session: GameSession
    let reveal: PourReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text("Target: \(reveal.targetPercent)%")
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
            return "Everyone spilled…"
        }
        return "🫗 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!"
    }

    private func error(_ r: PourResult) -> Int {
        guard let fill = r.fillPercent else { return Int.max }
        return r.overflowed ? 100_000 + fill : abs(fill - reveal.targetPercent)
    }

    private var sortedResults: [PourResult] {
        reveal.results.sorted { error($0) < error($1) }
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
                        Text("🫗")
                    }
                    Spacer()
                    if result.overflowed {
                        Text("spilled")
                            .font(Theme.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.magenta)
                    } else if let fill = result.fillPercent {
                        Text("\(fill)%")
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("no pour")
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
                    Text("Next glass in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
