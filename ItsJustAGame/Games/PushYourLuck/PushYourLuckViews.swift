import SwiftUI

/// Player chips for Push Your Luck: everyone's banked total, riders lit,
/// banked-this-run players dimmed with a lock.
struct DiceStatusBar: View {
    let session: GameSession
    let riders: [Int]
    let banks: [Int: Int]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(session.joinedSlots.sorted(), id: \.self) { slot in
                let riding = riders.contains(slot)
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.color(slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(slot))
                        .font(Theme.caption2)
                        .lineLimit(1)
                    Text("\(banks[slot, default: 0])")
                        .font(Theme.caption.weight(.bold))
                        .monospacedDigit()
                    if !riding {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(riding ? 1 : 0.55)
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

/// One choice: ride the pot or bank your share before the next die.
struct DiceStepView: View {
    let session: GameSession
    let step: DiceStep

    @State private var submitted = false

    private var amRiding: Bool { step.riders.contains(session.mySlot) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, step.deadline.timeIntervalSince(context.date))
            VStack(spacing: 16) {
                DiceStatusBar(session: session, riders: step.riders, banks: step.banks)
                Text("Run \(step.run) · bank \(GameTiming.diceBankTarget) to win")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Spacer()
                VStack(spacing: 4) {
                    Text("THE POT")
                        .font(Theme.kicker)
                        .foregroundStyle(.secondary)
                        .kerning(2)
                    Text("\(step.pot)")
                        .font(Theme.display(72))
                        .monospacedDigit()
                        .foregroundStyle(Theme.cyan)
                        .shadow(color: Theme.cyan.opacity(0.4), radius: 18)
                }
                Spacer()
                if !amRiding {
                    Text("You're safe with \(step.banks[session.mySlot, default: 0]) banked — watching the brave…")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else if submitted {
                    Text("Locked in — waiting for the others…")
                        .font(Theme.headline)
                } else {
                    Text("Ride it or take it? \(Int(remaining.rounded(.up)))s")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    if let hint = assistHint {
                        Text(hint.text)
                            .font(Theme.caption.weight(.semibold))
                            .foregroundStyle(hint.urgent ? Theme.magenta : Theme.cyan)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    HStack(spacing: 12) {
                        Button {
                            submit(push: true)
                        } label: {
                            Label("Push", systemImage: "dice.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.cyan))
                        Button {
                            submit(push: false)
                        } label: {
                            Label("Bank \(step.pot)", systemImage: "lock.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.magenta))
                    }
                    .padding(.horizontal, 24)
                }
                Spacer(minLength: 16)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedDice(for: step)
        }
    }

    /// Simplify: odds at level 1, straight advice at level 2, and at the
    /// top level the host's pre-rolled die — pure foreknowledge.
    private var assistHint: (text: String, urgent: Bool)? {
        guard let level = session.myAssist, amRiding else { return nil }
        switch level {
        case .little:
            return ("1 die in 6 is a skull", false)
        case .big:
            let mine = step.banks[session.mySlot, default: 0]
            if mine + step.pot >= GameTiming.diceBankTarget {
                return ("Bank it — that wins you the round!", false)
            }
            return step.pot >= 10
                ? ("That's a big pot — banking looks smart", false)
                : ("The pot's still small — riding looks fine", false)
        case .cheating:
            guard let skull = step.assistPeek?[session.mySlot] else { return nil }
            return skull
                ? ("😈 The next die is a SKULL — bank, now!", true)
                : ("😈 The next die is safe — ride it", false)
        }
    }

    private func submit(push: Bool) {
        guard !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitDice(push: push, for: step)
    }
}

/// The die lands: a fat number for the riders, a skull for the greedy.
struct DiceRevealView: View {
    let session: GameSession
    let reveal: DiceReveal

    var body: some View {
        VStack(spacing: 14) {
            DiceStatusBar(session: session, riders: reveal.riders, banks: reveal.banks)
            Text("Run \(reveal.run)")
                .font(Theme.kicker)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            Spacer()
            centerpiece
            bankedList
            Spacer()
            footer
            Spacer(minLength: 16)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var centerpiece: some View {
        if reveal.isSkull {
            VStack(spacing: 10) {
                Text("💀")
                    .font(.system(size: 76))
                Text("BUST!")
                    .font(Theme.display(36))
                    .foregroundStyle(Theme.magenta)
                if !reveal.choices.filter({ $0.value }).isEmpty {
                    Text("\(session.names(reveal.choices.filter { $0.value }.map(\.key).sorted())) lose the pot of \(reveal.potBefore).")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        } else if let die = reveal.die {
            VStack(spacing: 12) {
                Text("\(die)")
                    .font(Theme.display(56))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(width: 96, height: 96)
                    .background(Theme.cyan, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: Theme.cyan.opacity(0.45), radius: 18)
                Text("Pot is now \(reveal.potAfter)")
                    .font(Theme.display(24))
            }
        } else {
            VStack(spacing: 10) {
                Text("🔒")
                    .font(.system(size: 56))
                Text("Everyone banked — run over!")
                    .font(Theme.display(24))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder
    private var bankedList: some View {
        if !reveal.bankedNow.isEmpty {
            Text("🔒 \(session.names(reveal.bankedNow)) banked \(reveal.potBefore)")
                .font(Theme.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
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
                    Text(reveal.runOver ? "Next run in \(remaining)s" : "Next die in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
