import SwiftUI

/// One Showdown turn: rock, paper, scissors against the whole table.
/// Everyone throws in secret before the deadline; you score a win for
/// every player you beat (no throw loses to everyone who threw).
struct ShowdownTurnView: View {
    let session: GameSession
    let turn: ShowdownTurn

    @State private var myThrow: RPSThrow?
    @State private var submitted = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, turn.deadline.timeIntervalSince(context.date))
            VStack(spacing: 16) {
                DiceStatusBar(session: session, riders: session.joinedSlots.sorted(), banks: turn.totals)
                Text("Turn \(turn.turn) · first to \(GameTiming.showdownTarget) wins")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text(submitted ? "Thrown — waiting for the others…" : "Beat the whole table!")
                    .font(Theme.display(24))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
                throwButtons
                if !submitted {
                    Text("\(Int(remaining.rounded(.up)))s — you score a win for every player you beat")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                if let hint = assistHint {
                    Text(hint)
                        .font(Theme.caption.weight(.semibold))
                        .foregroundStyle(Theme.cyan)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedShowdown(for: turn)
            await autoSubmit()
        }
    }

    private var throwButtons: some View {
        HStack(spacing: 14) {
            ForEach(RPSThrow.allCases, id: \.self) { option in
                Button {
                    submit(option)
                } label: {
                    VStack(spacing: 6) {
                        Text(option.emoji)
                            .font(.system(size: 44))
                        Text(option.displayName)
                            .font(Theme.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
                .background(
                    (myThrow == option ? Theme.cyan.opacity(0.25) : Theme.quietFill),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(
                            myThrow == option
                                ? Theme.cyan
                                : (recommended == option ? Color.white.opacity(0.85) : Theme.hairline),
                            lineWidth: myThrow == option || recommended == option ? 2.5 : 1
                        )
                )
                .opacity(submitted && myThrow != option ? 0.4 : 1)
                .disabled(submitted)
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Simplify

    /// What the others have thrown so far, relayed live by the host for
    /// levels 2–3 (like Gold Rush's taken squares).
    private var seenThrows: [RPSThrow] {
        guard let level = session.myAssist, level >= .big,
              let seen = turn.assistThrown?[session.mySlot] else { return [] }
        return Array(seen.values)
    }

    /// Simplify (top level): the throw that beats the most of what's been
    /// thrown so far.
    private var recommended: RPSThrow? {
        guard session.myAssist == .cheating, !submitted, !seenThrows.isEmpty else { return nil }
        return RPSThrow.allCases.max { beatenCount($0) < beatenCount($1) }
    }

    private func beatenCount(_ option: RPSThrow) -> Int {
        seenThrows.filter { option.beats($0) }.count
    }

    private var assistHint: String? {
        guard let level = session.myAssist else { return nil }
        switch level {
        case .little:
            return "Paper beats rock · rock beats scissors · scissors beats paper"
        case .big:
            guard !seenThrows.isEmpty else { return "Nothing thrown yet — watch this space…" }
            let counts = RPSThrow.allCases.compactMap { option -> String? in
                let count = seenThrows.filter { $0 == option }.count
                return count > 0 ? "\(option.emoji)×\(count)" : nil
            }
            return "Thrown so far: \(counts.joined(separator: "  "))"
        case .cheating:
            guard let recommended else {
                return submitted ? nil : "😈 Nothing thrown yet — hold on a moment…"
            }
            return "😈 Throw \(recommended.emoji) — it beats the most right now"
        }
    }

    // MARK: - Input

    private func submit(_ option: RPSThrow) {
        guard !submitted else { return }
        submitted = true
        myThrow = option
        SoundPlayer.shared.play(.lockin)
        session.submitShowdown(throwing: option, for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        // A silent player gets a random throw rather than losing to the
        // whole table over a network blip.
        submit(RPSThrow.allCases.randomElement() ?? .rock)
    }
}

/// The reveal: everyone's throw side by side, wins counted.
struct ShowdownRevealView: View {
    let session: GameSession
    let reveal: ShowdownReveal

    var body: some View {
        VStack(spacing: 14) {
            DiceStatusBar(session: session, riders: session.joinedSlots.sorted(), banks: reveal.totals)
            Text("Turn \(reveal.turn) · first to \(GameTiming.showdownTarget) wins")
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
            return "Everyone cancels out — no wins!"
        }
        let best = reveal.winners.compactMap { reveal.gains[$0] }.max() ?? 0
        return "🥊 \(session.names(reveal.winners)) beat \(best) player\(best == 1 ? "" : "s")!"
    }

    private var sortedSlots: [Int] {
        session.joinedSlots.sorted {
            (reveal.gains[$0] ?? 0, $1) > (reveal.gains[$1] ?? 0, $0)
        }
    }

    private var resultsList: some View {
        VStack(spacing: 8) {
            ForEach(sortedSlots, id: \.self) { slot in
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.color(slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(slot))
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    Text(reveal.thrown[slot]?.emoji ?? "💤")
                    if reveal.winners.contains(slot) {
                        Text("🥊")
                    }
                    Spacer()
                    let gain = reveal.gains[slot] ?? 0
                    Text(gain > 0 ? "+\(gain)" : "—")
                        .font(Theme.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(gain > 0 ? Theme.cyan : .secondary)
                    Text("· \(reveal.totals[slot, default: 0])")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
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
                    Text("Next throw in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
