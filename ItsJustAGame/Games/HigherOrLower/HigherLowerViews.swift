import SwiftUI

/// A standard 52-card deck the host draws from, reshuffling when empty.
/// Lives here with the rest of the game so adding a card game later can
/// reuse it.
struct Deck {
    private var cards: [PlayingCard] = []

    mutating func draw() -> PlayingCard {
        if cards.isEmpty {
            cards = CardSuit.allCases.flatMap { suit in
                (1...13).map { PlayingCard(rank: $0, suit: suit) }
            }.shuffled()
        }
        return cards.removeFirst()
    }
}

extension PlayingCard {
    var rankText: String {
        switch rank {
        case 1: return "A"
        case 11: return "J"
        case 12: return "Q"
        case 13: return "K"
        default: return "\(rank)"
        }
    }

    var suitSymbol: String {
        switch suit {
        case .spades: return "suit.spade.fill"
        case .hearts: return "suit.heart.fill"
        case .diamonds: return "suit.diamond.fill"
        case .clubs: return "suit.club.fill"
        }
    }

    /// Red suits go magenta on our table; black suits stay ink.
    var suitColor: Color {
        switch suit {
        case .hearts, .diamonds: return Theme.magenta
        case .spades, .clubs: return Theme.ink
        }
    }
}

/// A drawn playing card — a bright white face that pops on the dark table.
struct PlayingCardView: View {
    let card: PlayingCard
    var width: CGFloat = 130

    var body: some View {
        let height = width * 1.4
        let corner = width * 0.11
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.white)
                .shadow(color: .black.opacity(0.55), radius: 14, y: 8)
            VStack {
                HStack {
                    cornerLabel
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    cornerLabel
                        .rotationEffect(.degrees(180))
                }
            }
            .padding(width * 0.08)
            Image(systemName: card.suitSymbol)
                .font(.system(size: width * 0.4))
                .foregroundStyle(card.suitColor)
        }
        .frame(width: width, height: height)
    }

    private var cornerLabel: some View {
        VStack(spacing: 1) {
            Text(card.rankText)
                .font(.system(size: width * 0.17, weight: .bold, design: .rounded))
                .foregroundStyle(card.suitColor)
            Image(systemName: card.suitSymbol)
                .font(.system(size: width * 0.1))
                .foregroundStyle(card.suitColor)
        }
    }
}

/// Player chips for Higher or Lower: match points as dots, eliminated
/// players dimmed and struck through.
struct HigherLowerStatusBar: View {
    let session: GameSession
    let alive: [Int]
    let points: [Int: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(session.joinedSlots.sorted(), id: \.self) { slot in
                let out = !alive.contains(slot)
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.color(slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(slot))
                        .font(Theme.caption2)
                        .lineLimit(1)
                        .strikethrough(out)
                    HStack(spacing: 3) {
                        ForEach(0..<GameTiming.pointsToWinRound, id: \.self) { index in
                            Circle()
                                .fill(index < points[slot, default: 0] ? session.color(slot) : Color.white.opacity(0.15))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
                .opacity(out ? 0.5 : 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.quietFill, in: Capsule())
                .overlay(
                    Capsule().stroke(
                        slot == session.mySlot ? Color.accentColor.opacity(0.5) : .clear,
                        lineWidth: 1.5
                    )
                )
            }
        }
        .padding(.horizontal)
    }
}

/// The guessing phase: the current card, and Higher (cyan) / Lower
/// (magenta) for everyone still standing.
struct CardGuessView: View {
    let session: GameSession
    let turn: CardTurn

    @State private var submitted = false

    private var amAlive: Bool { turn.alive.contains(session.mySlot) }

    /// Simplify: the call to nudge toward. Top level uses the host's
    /// pre-drawn truth; level 2 just plays the odds. Nil when even (7) or
    /// no help.
    private var assistCall: HigherLowerGuess? {
        guard let level = session.myAssist, amAlive else { return nil }
        if level == .cheating {
            // Nil on a tie — no glow, and the caption says you're safe.
            return turn.assistCorrect?[session.mySlot]
        }
        guard level >= .big else { return nil }
        let higherRanks = 13 - turn.card.rank
        let lowerRanks = turn.card.rank - 1
        if higherRanks == lowerRanks { return nil }
        return higherRanks > lowerRanks ? .higher : .lower
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, turn.deadline.timeIntervalSince(context.date))
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: turn.alive, points: turn.points)
                Text("Match \(turn.match)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text("Will the next card be…")
                    .font(Theme.display(24))
                PlayingCardView(card: turn.card, width: 150)
                    .padding(.vertical, 4)
                if !amAlive {
                    Text("You're out this match — watching…")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else if submitted {
                    Text("Locked in — waiting for the others…")
                        .font(Theme.headline)
                } else {
                    Text("\(Int(remaining.rounded(.up))) seconds")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button {
                            submit(.higher)
                        } label: {
                            Label("Higher", systemImage: "arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.cyan))
                        .overlay(
                            Capsule().stroke(
                                .white.opacity(assistCall == .higher ? 0.9 : 0),
                                lineWidth: 2.5
                            )
                        )
                        Button {
                            submit(.lower)
                        } label: {
                            Label("Lower", systemImage: "arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.magenta))
                        .overlay(
                            Capsule().stroke(
                                .white.opacity(assistCall == .lower ? 0.9 : 0),
                                lineWidth: 2.5
                            )
                        )
                    }
                    .padding(.horizontal, 24)
                    if let hint = assistHint {
                        Text(hint)
                            .font(Theme.caption)
                            .foregroundStyle(Theme.cyan)
                    }
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedGuess(for: turn)
            await autoSubmit()
        }
    }

    /// The caption under the buttons, escalating with the level.
    private var assistHint: String? {
        guard let level = session.myAssist, amAlive else { return nil }
        switch level {
        case .little:
            let higherRanks = 13 - turn.card.rank
            let lowerRanks = turn.card.rank - 1
            return "\(higherRanks) rank\(higherRanks == 1 ? " is" : "s are") higher · \(lowerRanks) lower"
        case .big:
            guard let call = assistCall else { return "Dead even — pure luck this time" }
            return "Better odds: \(call == .higher ? "Higher" : "Lower")"
        case .cheating:
            guard let truth = turn.assistCorrect?[session.mySlot] else {
                return "Psst… it's a tie — you're safe either way"
            }
            return "Psst… it's \(truth == .higher ? "Higher" : "Lower")"
        }
    }

    private func submit(_ guess: HigherLowerGuess) {
        guard !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitGuess(guess, for: turn)
    }

    private func autoSubmit() async {
        guard amAlive else { return }
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        submit(Bool.random() ? .higher : .lower)
    }
}

/// The flip: both cards side by side, everyone's call, who's out, and
/// either the next-card countdown or the match/round winners.
struct CardRevealView: View {
    let session: GameSession
    let reveal: CardReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: reveal.alive, points: reveal.points)
            Text(headline)
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HStack(spacing: 20) {
                PlayingCardView(card: reveal.previousCard, width: 100)
                    .opacity(0.6)
                Image(systemName: "arrow.right")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.secondary)
                PlayingCardView(card: reveal.nextCard, width: 130)
            }
            .padding(.vertical, 4)
            guessList
            footer
            Spacer()
        }
        .padding(.top, 8)
    }

    private var headline: String {
        if reveal.isTie {
            return "\(reveal.nextCard.rankText) again — a tie, everyone survives!"
        }
        let direction = reveal.nextCard.rank > reveal.previousCard.rank ? "Higher!" : "Lower!"
        if reveal.eliminated.isEmpty {
            return "\(direction) Everyone called it."
        }
        return "\(direction) \(session.names(reveal.eliminated)) \(reveal.eliminated.count == 1 ? "is" : "are") out."
    }

    private var guessList: some View {
        VStack(spacing: 6) {
            ForEach(reveal.guesses.keys.sorted(), id: \.self) { slot in
                if let guess = reveal.guesses[slot] {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(session.color(slot))
                            .frame(width: 8, height: 8)
                        Text(session.name(slot))
                            .font(Theme.subheadline)
                            .lineLimit(1)
                        Image(systemName: guess == .higher ? "arrow.up" : "arrow.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(guess == .higher ? Theme.cyan : Theme.magenta)
                        Spacer()
                        if reveal.isTie {
                            Text("safe")
                                .font(Theme.caption)
                                .foregroundStyle(.secondary)
                        } else if reveal.eliminated.contains(slot) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.magenta)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.cyan)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if !reveal.roundWinners.isEmpty {
                    Text("🏆 \(session.names(reveal.roundWinners)) \(reveal.roundWinners.count == 1 ? "wins" : "win") the round!")
                        .font(Theme.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if !reveal.matchWinners.isEmpty {
                    Text("🎯 \(session.names(reveal.matchWinners)) \(reveal.matchWinners.count == 1 ? "takes" : "take") the point — next match soon…")
                        .font(Theme.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let next = reveal.nextAt {
                    let remaining = Int(max(0, next.timeIntervalSince(context.date)).rounded(.up))
                    Text("Next card in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
