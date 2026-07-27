import SwiftUI

/// One Crack the Safe turn: twist the phone like a dial to spin each digit
/// of the combo into place. The combo is known (shown at the top) — the
/// skill is turning to each number and settling on it, fastest wins. Only
/// the elapsed time leaves the phone.
struct SafeTurnView: View {
    let session: GameSession
    let turn: SafeTurn

    @State private var submitted = false
    @State private var dialAngle: Double = 0
    @State private var lastTick: Date?
    @State private var locked: [Int] = []
    @State private var settleStart: Date?

    private var motion: MotionService { MotionService.shared }

    /// The digit currently under the pointer, 0–9.
    private var currentDigit: Int {
        (((Int((dialAngle / 36).rounded()) % 10) + 10) % 10)
    }

    /// The combo digit we're dialling for right now (nil once all are in).
    private var activeTarget: Int? {
        locked.count < turn.combo.count ? turn.combo[locked.count] : nil
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.03)) { context in
            let now = context.date
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · crack the safe")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.3)
                header(now: now)
                comboRow
                Spacer(minLength: 8)
                dial
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .onChange(of: context.date) { _, newDate in
                advance(now: newDate)
            }
        }
        .task {
            submitted = session.hasSubmittedSafe(for: turn)
            motion.start()
            await autoFinish()
        }
        .onDisappear { motion.stop() }
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        if submitted && locked.count == turn.combo.count {
            Text("Cracked! — waiting…").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else if submitted {
            Text("Time's up — waiting…").font(Theme.headline)
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if !motion.isAvailable {
            Text("This game needs a real device")
                .font(Theme.subheadline).foregroundStyle(Theme.magenta)
        } else {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("Twist to each number · \(remaining)s").font(Theme.display(20))
        }
    }

    private var comboRow: some View {
        HStack(spacing: 14) {
            ForEach(0..<turn.combo.count, id: \.self) { i in
                let isLocked = i < locked.count
                let isActive = i == locked.count && !submitted
                Text("\(turn.combo[i])")
                    .font(Theme.display(30)).monospacedDigit()
                    .frame(width: 52, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isLocked ? Theme.cyan.opacity(0.22) : Theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isActive ? Theme.magenta : Theme.hairline, lineWidth: isActive ? 2 : 1)
                    )
                    .foregroundStyle(isLocked ? Theme.cyan : .primary)
                    .overlay(alignment: .topTrailing) {
                        if isLocked {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(Theme.cyan).padding(4)
                        }
                    }
            }
        }
    }

    private var dial: some View {
        let onTarget = activeTarget == currentDigit
        let live = !submitted
        return ZStack {
            Circle().stroke(Theme.hairline, lineWidth: 2)
            ZStack {
                ForEach(0..<10, id: \.self) { d in
                    Text("\(d)")
                        .font(Theme.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .offset(y: -96)
                        .rotationEffect(.degrees(Double(d) * 36))
                }
            }
            .rotationEffect(.degrees(-dialAngle))
            Image(systemName: "arrowtriangle.down.fill")
                .foregroundStyle(Theme.magenta)
                .offset(y: -108)
            Text("\(currentDigit)")
                .font(Theme.display(72)).monospacedDigit()
                .foregroundStyle(highlightsTarget && onTarget && live ? Color.green : Theme.cyan)
        }
        .frame(width: 220, height: 220)
        .padding(.horizontal, 24)
    }

    // MARK: - Dial physics

    private func advance(now: Date) {
        guard now >= turn.startAt, now < turn.deadline, !submitted else {
            lastTick = now
            return
        }
        let dt = lastTick.map { now.timeIntervalSince($0) } ?? 0
        lastTick = now
        guard dt > 0, dt < 0.2 else { return }
        // Twisting the phone about the screen-normal spins the dial. On a
        // real device the sign feels natural; flip here if a tester finds
        // it backwards.
        dialAngle += motion.twistRateDegrees * dt

        guard let target = activeTarget else { return }
        let onTarget = currentDigit == target
        if session.myAssist == .cheating {
            if onTarget { lockDigit() }
            return
        }
        let steady = abs(motion.twistRateDegrees) < steadyThreshold
        if onTarget && steady {
            if settleStart == nil {
                settleStart = now
            } else if now.timeIntervalSince(settleStart!) >= dwellSeconds {
                lockDigit()
            }
        } else {
            settleStart = nil
        }
    }

    private func lockDigit() {
        settleStart = nil
        locked.append(currentDigit)
        SoundPlayer.shared.play(.tick)
        if locked.count == turn.combo.count { finish() }
    }

    private func finish() {
        guard !submitted else { return }
        submitted = true
        let elapsed = Int(max(0, Date().timeIntervalSince(turn.startAt)) * 1000)
        SoundPlayer.shared.play(.lockin)
        session.submitSafe(elapsedMs: elapsed, for: turn)
    }

    /// Deadline reached without cracking it — stop dialling and let the host
    /// record "no crack" for us.
    private func autoFinish() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
    }

    // MARK: - Simplify

    /// Any assist makes "settled" more forgiving.
    private var steadyThreshold: Double { session.myAssist == nil ? 55 : 120 }

    private var dwellSeconds: Double {
        switch session.myAssist {
        case .big: return 0.3
        case .little: return 0.45
        default: return 0.6
        }
    }

    /// The centre digit turns green when it matches the target (levels 2–3).
    private var highlightsTarget: Bool {
        guard let level = session.myAssist else { return false }
        return level >= .big
    }
}

/// Fastest to crack the safe takes the point.
struct SafeRevealView: View {
    let session: GameSession
    let reveal: SafeReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Combo \(reveal.combo.map(String.init).joined(separator: " · "))",
            headline: reveal.winners.isEmpty
                ? "Nobody cracked it…"
                : "🔓 \(session.names(reveal.winners)) cracked it first!",
            rows: reveal.results
                .sorted { ($0.elapsedMs ?? .max) < ($1.elapsedMs ?? .max) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🔓",
                              value: r.elapsedMs.map { String(format: "%.1fs", Double($0) / 1000) },
                              empty: "locked out")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next safe"
        )
    }
}
