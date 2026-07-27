import SwiftUI

/// The four Stroop colours — bright on the dark table, and always
/// labelled by name so the button is identifiable, not just by hue.
enum ClashPalette {
    static let colours: [Color] = [
        Color(red: 1.00, green: 0.29, blue: 0.31),  // red
        Color(red: 0.28, green: 0.84, blue: 0.44),  // green
        Color(red: 0.30, green: 0.56, blue: 1.00),  // blue
        Color(red: 1.00, green: 0.82, blue: 0.24),  // yellow
    ]
    static let names = ["Red", "Green", "Blue", "Yellow"]
}

/// One prompt: a colour *word* printed in a (usually clashing) *ink*.
/// You tap the ink. Regenerated identically on every device from the seed.
struct ClashPrompt {
    let word: Int
    let ink: Int
}

enum ClashDeck {
    static func prompts(seed: UInt64, count: Int) -> [ClashPrompt] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            let word = Int.random(in: 0..<4, using: &generator)
            // ~75% of prompts clash (ink ≠ word); the rest match, for rhythm.
            let clash = Int.random(in: 0..<4, using: &generator) != 0
            let ink = clash ? (word + Int.random(in: 1...3, using: &generator)) % 4 : word
            return ClashPrompt(word: word, ink: ink)
        }
    }
}

/// One Colour Clash turn: tap the ink colour of each word, resisting the
/// word itself, as fast as you can. Time runs locally from the shared
/// start; wrong taps add a second.
struct ClashTurnView: View {
    let session: GameSession
    let turn: ClashTurn

    @State private var index = 0
    @State private var penaltyMs = 0
    @State private var wrongFlash: Int?
    @State private var resultMs: Int?
    @State private var submitted = false
    @State private var lastProgressAt: Date?

    private let prompts: [ClashPrompt]

    init(session: GameSession, turn: ClashTurn) {
        self.session = session
        self.turn = turn
        self.prompts = ClashDeck.prompts(seed: turn.seed, count: turn.promptCount)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · tap the colour, not the word")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                header(now: now)
                Spacer(minLength: 4)
                prompt(now: now)
                Spacer(minLength: 4)
                buttons(now: now)
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedClash(for: turn)
            if submitted { resultMs = 0 }
        }
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        if let resultMs, resultMs > 0 {
            Text("You: \(timeString(resultMs)) — waiting…")
                .font(Theme.display(22))
        } else if submitted {
            Text("Locked in — waiting…")
                .font(Theme.display(22))
        } else if now < turn.startAt {
            Text("Get ready…")
                .font(Theme.display(24))
        } else if now >= turn.deadline {
            Text("Time's up — waiting for the reveal…")
                .font(Theme.headline)
        } else {
            let elapsed = Int(now.timeIntervalSince(turn.startAt) * 1000) + penaltyMs
            HStack(spacing: 12) {
                Text("\(min(index + 1, turn.promptCount)) of \(turn.promptCount)")
                    .font(Theme.display(22))
                    .foregroundStyle(Theme.cyan)
                Text(timeString(elapsed))
                    .font(Theme.display(22))
                    .monospacedDigit()
                    .foregroundStyle(penaltyMs > 0 ? Theme.magenta : .white)
            }
        }
    }

    @ViewBuilder
    private func prompt(now: Date) -> some View {
        let live = !submitted && now >= turn.startAt && now < turn.deadline && index < prompts.count
        ZStack {
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .fill(Theme.surface)
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
            if live {
                let p = prompts[index]
                Text(ClashPalette.names[p.word].uppercased())
                    .font(Font.custom(Theme.BrandFont.bold, size: 52))
                    .foregroundStyle(ClashPalette.colours[p.ink])
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 20)
            } else {
                Text(submitted || (now >= turn.deadline) ? "✓" : "…")
                    .font(Theme.display(40))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 130)
        .padding(.horizontal, 24)
    }

    private func buttons(now: Date) -> some View {
        let live = !submitted && now >= turn.startAt && now < turn.deadline && index < prompts.count
        let answer = live ? prompts[index].ink : -1
        return LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(0..<4, id: \.self) { i in
                let hinted = live && hintActive(now: now) && i == answer
                Button {
                    tap(colour: i, now: Date())
                } label: {
                    Text(ClashPalette.names[i])
                        .font(Font.custom(Theme.BrandFont.semiBold, size: 17))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                }
                .background(ClashPalette.colours[i].opacity(0.9), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            wrongFlash == i ? .white : (hinted ? .white : .clear),
                            lineWidth: wrongFlash == i ? 3 : (hinted ? 3 : 0)
                        )
                )
                .shadow(color: hinted ? .white.opacity(0.6) : .clear, radius: 8)
                .disabled(!live)
            }
        }
        .padding(.horizontal, 24)
    }

    /// Simplify: whether the correct button should glow now. Level 1 only
    /// after a couple of stuck seconds; levels 2–3 always.
    private func hintActive(now: Date) -> Bool {
        guard let level = session.myAssist else { return false }
        switch level {
        case .little:
            return now.timeIntervalSince(lastProgressAt ?? turn.startAt) > 2.0
        case .big, .cheating:
            return true
        }
    }

    private func tap(colour: Int, now: Date) {
        guard !submitted,
              now >= turn.startAt,
              now < turn.deadline,
              index < prompts.count else { return }
        if colour == prompts[index].ink {
            SoundPlayer.shared.play(.tick)
            index += 1
            lastProgressAt = now
            if index >= turn.promptCount {
                let elapsed = Int(now.timeIntervalSince(turn.startAt) * 1000) + penaltyMs
                resultMs = elapsed
                submitted = true
                SoundPlayer.shared.play(.lockin)
                session.submitClash(
                    elapsedMs: elapsed,
                    mistakes: penaltyMs / GameTiming.clashPenaltyMs,
                    for: turn
                )
            }
        } else {
            if session.myAssist != .cheating {
                // Simplify (top level): slips are shown but cost no time.
                penaltyMs += GameTiming.clashPenaltyMs
            }
            wrongFlash = colour
            Task {
                try? await Task.sleep(for: .seconds(0.25))
                if wrongFlash == colour { wrongFlash = nil }
            }
        }
    }

    private func timeString(_ ms: Int) -> String {
        String(format: "%.2fs", Double(ms) / 1000)
    }
}

/// Fastest clean(ish) run takes the point.
struct ClashRevealView: View {
    let session: GameSession
    let reveal: ClashReveal

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
            return "Nobody made it through…"
        }
        return "🎨 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") fastest!"
    }

    private var sortedResults: [ClashResult] {
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
                        Text("🎨")
                    }
                    Spacer()
                    if let elapsedMs = result.elapsedMs {
                        Text(String(format: "%.2fs", Double(elapsedMs) / 1000))
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                        if result.mistakes > 0 {
                            Text("(\(result.mistakes) slip\(result.mistakes == 1 ? "" : "s"))")
                                .font(Theme.caption)
                                .foregroundStyle(Theme.magenta)
                        }
                    } else {
                        Text("didn't finish")
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
                    Text("Next colours in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
