import SwiftUI

/// One Eyeball It turn: the dot cloud flashes (identical on every device,
/// regenerated from the turn's seed), vanishes, and everyone dials in a
/// guess.
struct EyeballTurnView: View {
    let session: GameSession
    let turn: EyeballTurn

    @State private var guess: Double
    @State private var submitted = false
    /// When this device actually drew the dots — the visible window runs
    /// from here, so polling latency can't eat into it.
    @State private var dotsShownAt: Date?

    private let dots: [SharedLayout.Dot]
    /// Simplify (levels 2–3): the slider narrows around the true count,
    /// jittered by a seeded offset so its middle isn't the answer.
    private let sliderRange: ClosedRange<Double>
    private let assist: AssistLevel?

    init(session: GameSession, turn: EyeballTurn) {
        self.session = session
        self.turn = turn
        self.dots = SharedLayout.dots(seed: turn.seed, count: turn.count)
        let assist = session.myAssist
        self.assist = assist
        if let assist, assist >= .big {
            var generator = SeededGenerator(seed: turn.seed &+ UInt64(max(0, session.mySlot)))
            let jitter = Double(Int.random(in: -6...6, using: &generator))
            let halfWidth: Double = assist == .cheating ? 12 : 30
            let center = Double(turn.count) + jitter
            let lower = max(10, min(center - halfWidth, 200 - halfWidth * 2))
            let upper = min(200, lower + halfWidth * 2)
            self.sliderRange = lower...upper
        } else {
            self.sliderRange = 10...200
        }
        _guess = State(initialValue: (sliderRange.lowerBound + sliderRange.upperBound) / 2)
    }

    /// Simplify: the dots hang around longer before vanishing.
    private var localVisibleSeconds: Double {
        switch assist {
        case nil: return turn.visibleSeconds
        case .little: return turn.visibleSeconds * 1.6
        case .big, .cheating: return turn.visibleSeconds * 2.2
        }
    }

    /// The full visible window counts from the moment THIS device rendered
    /// the dots, not from the shared start — a message that arrives a
    /// second late must not cost a second of looking time. A device
    /// arriving long after the window (a mid-turn rejoin) skips the dots
    /// and goes straight to guessing.
    private func showingDots(now: Date) -> Bool {
        guard !submitted, now <= turn.deadline else { return false }
        if let dotsShownAt {
            return now < dotsShownAt.addingTimeInterval(localVisibleSeconds)
        }
        return now < turn.startAt.addingTimeInterval(localVisibleSeconds + 3)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                if now < turn.startAt {
                    Text("Get ready…")
                        .font(Theme.display(26))
                    Spacer()
                } else if showingDots(now: now) {
                    Text("How many dots?")
                        .font(Theme.display(26))
                    dotField
                        .onAppear {
                            if dotsShownAt == nil {
                                dotsShownAt = Date()
                            }
                        }
                    Spacer()
                } else if submitted {
                    Text("Locked in!")
                        .font(Theme.display(26))
                    Text("Counts at the reveal…")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else if now > turn.deadline {
                    Text("Time's up — waiting for the reveal…")
                        .font(Theme.headline)
                    Spacer()
                } else {
                    let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
                    Text("How many were there?")
                        .font(Theme.display(26))
                    guessControls(remaining: remaining)
                    Spacer()
                }
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedEyeball(for: turn)
            await autoSubmit()
        }
    }

    private var dotField: some View {
        Canvas { context, size in
            for dot in dots {
                let rect = CGRect(
                    x: dot.x * size.width - dot.radius * size.width,
                    y: dot.y * size.height - dot.radius * size.width,
                    width: dot.radius * 2 * size.width,
                    height: dot.radius * 2 * size.width
                )
                let color: Color = dot.tint == 0 ? Theme.cyan : (dot.tint == 1 ? Theme.magenta : .white)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.9)))
            }
        }
        .frame(width: 320, height: 320)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private func guessControls(remaining: Int) -> some View {
        VStack(spacing: 14) {
            Text("\(Int(guess))")
                .font(Theme.display(56))
                .monospacedDigit()
                .foregroundStyle(Theme.cyan)
            Slider(value: $guess, in: sliderRange, step: 1)
                .tint(Theme.cyan)
                .padding(.horizontal, 32)
            if assist == .cheating {
                Text("It's between \(Int(sliderRange.lowerBound)) and \(Int(sliderRange.upperBound))")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.cyan)
            }
            HStack(spacing: 10) {
                nudge(-10)
                nudge(-1)
                nudge(1)
                nudge(10)
            }
            Text("\(remaining)s")
                .font(Theme.caption)
                .foregroundStyle(.secondary)
            Button {
                submit()
            } label: {
                Label("Lock in \(Int(guess))", systemImage: "eye.fill")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func nudge(_ amount: Int) -> some View {
        Button {
            guess = min(sliderRange.upperBound, max(sliderRange.lowerBound, guess + Double(amount)))
        } label: {
            Text(amount > 0 ? "+\(amount)" : "\(amount)")
                .monospacedDigit()
                .frame(minWidth: 40)
        }
        .buttonStyle(QuietButtonStyle())
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitEyeball(guess: Int(guess), for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        submit()
    }
}

/// The true count, and everyone's guess ranked by distance.
struct EyeballRevealView: View {
    let session: GameSession
    let reveal: EyeballReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text("There were")
                .font(Theme.kicker)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            Text("\(reveal.count)")
                .font(Theme.display(64))
                .monospacedDigit()
                .foregroundStyle(Theme.cyan)
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
            return "Nobody guessed that time…"
        }
        return "👀 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!"
    }

    private var sortedResults: [EyeballResult] {
        reveal.results.sorted { ($0.error ?? .max) < ($1.error ?? .max) }
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
                        Text("👀")
                    }
                    Spacer()
                    if let guess = result.guess, let error = result.error {
                        Text("\(guess)")
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Text("(\(error) off)")
                            .font(Theme.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("no guess")
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
                    Text("Next cloud in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
