import SwiftUI

/// One Loudest turn: on GO, shout — the loudest peak wins. Only a number
/// (0–1000) leaves the phone; no audio is recorded.
struct LoudTurnView: View {
    let session: GameSession
    let turn: LoudTurn

    @State private var submitted = false
    @State private var micDenied = false

    private var mic: MicService { MicService.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let now = context.date
            let live = now >= turn.startAt && now < turn.deadline && !submitted
            VStack(spacing: 16) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · shout!")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                header(now: now, live: live)
                Spacer()
                meter(live: live)
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedLoud(for: turn)
            if submitted { return }
            let ok = await mic.start()
            micDenied = !ok
            mic.resetPeak()
            await autoSubmit()
        }
        .onDisappear { mic.stop() }
    }

    @ViewBuilder
    private func header(now: Date, live: Bool) -> some View {
        if submitted {
            Text("Nice lungs! — waiting…").font(Theme.display(24))
        } else if micDenied {
            Text("Microphone needed for this one")
                .font(Theme.subheadline).foregroundStyle(Theme.magenta)
        } else if now < turn.startAt {
            let count = Int(turn.startAt.timeIntervalSince(now).rounded(.up))
            Text(count > 0 ? "Get ready… \(count)" : "GO!").font(Theme.display(30))
        } else if live {
            Text("GO — SHOUT! 🗣️").font(Theme.display(34)).foregroundStyle(Theme.cyan)
        } else {
            Text("Time's up — waiting…").font(Theme.headline)
        }
    }

    private func meter(live: Bool) -> some View {
        // The bar tracks the live level so it feels responsive; the number is
        // the sustained score, which is what actually counts.
        let value = live ? mic.level : mic.sustainedPeak
        return VStack(spacing: 12) {
            GeometryReader { proxy in
                let w = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface).overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.cyan, Theme.magenta], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, w * value))
                }
            }
            .frame(height: 40)
            Text("\(Self.loudScore(mic.sustainedPeak))")
                .font(Theme.display(40)).monospacedDigit()
                .foregroundStyle(Theme.cyan)
        }
        .padding(.horizontal, 32)
    }

    /// 0–1 sustained loudness → 0–1000, with a curve so the top is genuinely
    /// hard: you have to be very loud, for a good second, to near 1000.
    static func loudScore(_ raw: Double) -> Int {
        Int((pow(min(1.0, max(0, raw)), 1.5) * 1000).rounded())
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submitted = true
        // Simplify quietly scales your loudness up.
        let boost: Double
        switch session.myAssist {
        case .little: boost = 1.15
        case .big: boost = 1.3
        case .cheating: boost = 1.6
        default: boost = 1.0
        }
        let level = min(1000, Self.loudScore(mic.sustainedPeak * boost))
        SoundPlayer.shared.play(.lockin)
        session.submitLoud(level: level, for: turn)
    }
}

struct LoudRevealView: View {
    let session: GameSession
    let reveal: LoudReveal

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "Turn \(reveal.turn)",
            headline: reveal.winners.isEmpty ? "Silence…" : "🗣️ \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") loudest!",
            rows: reveal.results
                .sorted { ($0.level ?? -1) > ($1.level ?? -1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "🗣️",
                              value: r.level.map { "\($0)" }, empty: "silent")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next shout"
        )
    }
}
