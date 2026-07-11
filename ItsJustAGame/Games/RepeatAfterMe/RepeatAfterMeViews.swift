import SwiftUI

enum SequencePads {
    /// Pad colors: the brand pair plus lime and amber from the player palette.
    static let colors: [Color] = [
        Theme.cyan,
        Theme.magenta,
        PlayerStyle.palette[2],
        PlayerStyle.palette[3],
    ]
}

/// The 2×2 pad board. Flashing (during the watch phase) and tap feedback
/// both light a pad to full brightness with a neon glow.
struct SequencePadBoard: View {
    var highlighted: Int?
    var tapsEnabled: Bool
    var onTap: (Int) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            ForEach(0..<4, id: \.self) { pad in
                let active = highlighted == pad
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SequencePads.colors[pad].opacity(active ? 1 : 0.28))
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: SequencePads.colors[pad].opacity(active ? 0.6 : 0), radius: 18)
                    .animation(.easeOut(duration: 0.12), value: active)
                    .onTapGesture {
                        if tapsEnabled {
                            onTap(pad)
                        }
                    }
            }
        }
        .padding(.horizontal, 44)
    }
}

/// One turn: watch the sequence flash from the shared start timestamp,
/// then tap it back before the deadline. Wrong or late means elimination —
/// the host validates.
struct SequenceTurnView: View {
    let session: GameSession
    let turn: SequenceTurn

    @State private var taps: [Int] = []
    @State private var tapFlash: Int?
    @State private var submitted = false

    private var amAlive: Bool { turn.alive.contains(session.mySlot) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            let watching = now < turn.watchEndsAt
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: turn.alive, points: turn.points)
                Text("Match \(turn.match) · \(turn.sequence.count) flashes")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                header(now: now, watching: watching)
                SequencePadBoard(
                    highlighted: watching ? watchHighlight(at: now) : tapFlash,
                    tapsEnabled: canTap(now: now),
                    onTap: { pad in tap(pad) }
                )
                progressDots(watching: watching)
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedSequence(for: turn)
            await autoSubmit()
        }
    }

    private func header(now: Date, watching: Bool) -> some View {
        Group {
            if !amAlive {
                Text("You're out this match — watching…")
                    .font(Theme.headline)
                    .foregroundStyle(.secondary)
            } else if now < turn.startAt {
                Text("Get ready…")
                    .font(Theme.display(24))
            } else if watching {
                Text("Watch carefully…")
                    .font(Theme.display(24))
            } else if submitted {
                Text("Locked in — waiting…")
                    .font(Theme.display(24))
            } else {
                let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
                Text("Repeat it! \(remaining)s")
                    .font(Theme.display(24))
            }
        }
    }

    /// Which pad is lit during the watch phase, driven purely by the shared
    /// start timestamp so every device flashes in step.
    private func watchHighlight(at now: Date) -> Int? {
        let elapsed = now.timeIntervalSince(turn.startAt) - 1.0
        guard elapsed >= 0 else { return nil }
        let flash = GameTiming.sequenceFlashSeconds
        let index = Int(elapsed / flash)
        guard index >= 0 && index < turn.sequence.count else { return nil }
        // Dark gap at the end of each flash so repeats of the same pad read
        // as separate flashes.
        let fraction = elapsed / flash - Double(index)
        return fraction < 0.72 ? turn.sequence[index] : nil
    }

    private func canTap(now: Date) -> Bool {
        amAlive && !submitted && now >= turn.watchEndsAt && now < turn.deadline
    }

    private func tap(_ pad: Int) {
        taps.append(pad)
        tapFlash = pad
        Task {
            try? await Task.sleep(for: .seconds(0.15))
            if tapFlash == pad { tapFlash = nil }
        }
        if taps.count == turn.sequence.count {
            submit()
        }
    }

    private func progressDots(watching: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<turn.sequence.count, id: \.self) { index in
                Circle()
                    .fill(dotColor(index: index, watching: watching))
                    .frame(width: 10, height: 10)
            }
        }
    }

    private func dotColor(index: Int, watching: Bool) -> Color {
        if !watching, amAlive, index < taps.count {
            return SequencePads.colors[taps[index]]
        }
        return Color.white.opacity(0.15)
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        session.submitSequence(taps: taps, for: turn)
    }

    private func autoSubmit() async {
        guard amAlive else { return }
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        // Whatever was tapped goes in; short or empty means elimination.
        submit()
    }
}

/// After each turn: the true sequence, who matched it, who fell.
struct SequenceRevealView: View {
    let session: GameSession
    let reveal: SequenceReveal

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: reveal.alive, points: reveal.points)
            Text(headline)
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            VStack(spacing: 8) {
                Text("The sequence")
                    .font(Theme.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.2)
                HStack(spacing: 6) {
                    ForEach(reveal.sequence.indices, id: \.self) { index in
                        Circle()
                            .fill(SequencePads.colors[reveal.sequence[index]])
                            .frame(width: 14, height: 14)
                    }
                }
            }
            .card()
            .padding(.horizontal, 24)
            resultsList
            footer
            Spacer()
        }
        .padding(.top, 8)
    }

    private var headline: String {
        if reveal.eliminated.isEmpty {
            return "Everyone nailed it — it gets longer!"
        }
        return "\(session.names(reveal.eliminated)) \(reveal.eliminated.count == 1 ? "is" : "are") out."
    }

    private var resultsList: some View {
        VStack(spacing: 6) {
            ForEach(reveal.results) { result in
                HStack(spacing: 8) {
                    Circle()
                        .fill(PlayerStyle.color(for: result.slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(result.slot))
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if result.correct {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.cyan)
                    } else {
                        Text(missText(for: result))
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.magenta)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private func missText(for result: SequencePlayerResult) -> String {
        guard let taps = result.taps else { return "no answer" }
        if taps.count < reveal.sequence.count {
            return "\(taps.count) of \(reveal.sequence.count)"
        }
        return "wrong pad"
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
                    Text("Next sequence in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
