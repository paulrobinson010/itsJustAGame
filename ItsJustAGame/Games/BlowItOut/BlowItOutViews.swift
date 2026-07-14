import SwiftUI

/// One Blow It Out turn: blow at the phone to snuff the candles. The device
/// integrates loudness over the window into a candle count; most out wins.
struct BlowTurnView: View {
    let session: GameSession
    let turn: BlowTurn

    @State private var blown = 0.0
    @State private var submitted = false
    @State private var micDenied = false

    private var mic: MicService { MicService.shared }

    private var candlesOut: Int { min(turn.candles, Int(blown)) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · blow them out!")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.4)
                header(now: now)
                Spacer()
                cake
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedBlow(for: turn)
            if submitted { return }
            let ok = await mic.start()
            micDenied = !ok
            await run()
        }
        .onDisappear { mic.stop() }
    }

    @ViewBuilder
    private func header(now: Date) -> some View {
        if submitted {
            Text("\(candlesOut) of \(turn.candles) out! — waiting…")
                .font(Theme.display(22)).multilineTextAlignment(.center)
        } else if micDenied {
            Text("Microphone needed for this one")
                .font(Theme.subheadline).foregroundStyle(Theme.magenta)
        } else if now < turn.startAt {
            let count = Int(turn.startAt.timeIntervalSince(now).rounded(.up))
            Text("Get ready… \(count)").font(Theme.display(26))
        } else {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("BLOW! 💨 · \(remaining)s").font(Theme.display(28)).foregroundStyle(Theme.cyan)
        }
    }

    private var cake: some View {
        let lit = turn.candles - candlesOut
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                ForEach(0..<turn.candles, id: \.self) { i in
                    Text(i < lit ? "🕯️" : "▪️")
                        .font(.system(size: 30))
                        .opacity(i < lit ? 1 : 0.35)
                }
            }
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .frame(height: 46)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1))
                .overlay(Text("🎂").font(.system(size: 30)))
                .padding(.horizontal, 24)
        }
    }

    private func run() async {
        while Date() < turn.startAt && !Task.isCancelled { try? await Task.sleep(for: .seconds(0.02)) }
        var last = Date()
        // How much integrated loudness snuffs one candle (lower = easier).
        let perCandle = 0.9
        let assistScale: Double
        switch session.myAssist {
        case .little: assistScale = 1.3
        case .big: assistScale = 1.6
        case .cheating: assistScale = 2.0
        default: assistScale = 1.0
        }
        while !Task.isCancelled, !submitted {
            try? await Task.sleep(for: .seconds(1.0 / 60.0))
            let now = Date()
            let dt = now.timeIntervalSince(last); last = now
            if now >= turn.deadline { submit(); break }
            // Only loud sustained sound counts as a blow.
            let strength = max(0, mic.level - 0.35)
            blown += strength * assistScale / perCandle * dt * 4
            if Int(blown) >= turn.candles { blown = Double(turn.candles); submit(); break }
        }
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitBlow(candles: candlesOut, for: turn)
    }
}

struct BlowRevealView: View {
    let session: GameSession
    let reveal: BlowReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty ? "Nobody had the puff…" : "💨 \(session.names(reveal.winners)) blew out the most!",
            rows: reveal.results
                .sorted { ($0.candles ?? -1) > ($1.candles ?? -1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "💨",
                              value: r.candles.map { "\($0)/\(reveal.candleCount)" }, empty: "no mic")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next cake"
        )
    }
}
