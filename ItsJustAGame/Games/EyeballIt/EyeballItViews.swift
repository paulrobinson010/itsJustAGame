import SwiftUI

/// One Eyeball It turn: the dot cloud flashes (identical on every device,
/// regenerated from the turn's seed), vanishes, and everyone dials in a
/// guess.
struct EyeballTurnView: View {
    let session: GameSession
    let turn: EyeballTurn

    @State private var guess: Double = 75
    @State private var submitted = false

    private let dots: [SharedLayout.Dot]

    init(session: GameSession, turn: EyeballTurn) {
        self.session = session
        self.turn = turn
        self.dots = SharedLayout.dots(seed: turn.seed, count: turn.count)
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
                } else if now < turn.dotsEndAt {
                    Text("How many dots?")
                        .font(Theme.display(26))
                    dotField
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
            Slider(value: $guess, in: 10...200, step: 1)
                .tint(Theme.cyan)
                .padding(.horizontal, 32)
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
            guess = min(200, max(10, guess + Double(amount)))
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
