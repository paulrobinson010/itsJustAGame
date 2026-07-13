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
                    Text("bank it and it's yours — a 💀 burns it")
                        .font(Theme.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if step.autoBanked?.contains(session.mySlot) == true {
                    Text("🎉 The pot carried you to \(GameTiming.diceBankTarget) — banked automatically!")
                        .font(Theme.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else if !amRiding {
                    Text("You're safe with \(step.banks[session.mySlot, default: 0]) banked — watching the brave…")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                } else if submitted {
                    Text("Locked in — waiting for the others…")
                        .font(Theme.headline)
                } else {
                    Text("Ride the next spin or take the pot? \(Int(remaining.rounded(.up)))s")
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
                            Label("Ride", systemImage: "arrow.triangle.2.circlepath")
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
            return ("2 spins in 7 land on a 💀", false)
        case .big:
            return step.pot >= 9
                ? ("That's a big pot — banking looks smart", false)
                : ("The pot's still small — riding looks fine", false)
        case .cheating:
            guard let bust = step.assistPeek?[session.mySlot] else { return nil }
            return bust
                ? ("😈 The next spin is a BUST — bank, now!", true)
                : ("😈 The next spin is safe — ride it", false)
        }
    }

    private func submit(push: Bool) {
        guard !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitDice(push: push, for: step)
    }
}

/// The pot wheel spins and lands: a number grows the pot, a 💀 burns it.
struct DiceRevealView: View {
    let session: GameSession
    let reveal: DiceReveal

    @State private var rotation: Double = 0
    @State private var finished = false

    var body: some View {
        VStack(spacing: 14) {
            DiceStatusBar(session: session, riders: reveal.riders, banks: reveal.banks)
            Text("Run \(reveal.run)")
                .font(Theme.kicker)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            Spacer()
            if reveal.wheelIndex != nil && !finished {
                VStack(spacing: 14) {
                    DiceWheelView(rotation: rotation)
                        .frame(width: 250, height: 250)
                    Text("Round it goes…")
                        .font(Theme.headline)
                        .foregroundStyle(.secondary)
                }
            } else {
                centerpiece
                bankedList
            }
            Spacer()
            footer
            Spacer(minLength: 16)
        }
        .padding(.top, 8)
        .task { await spin() }
    }

    private func spin() async {
        guard let wheelIndex = reveal.wheelIndex else {
            finished = true
            return
        }
        let spinSeconds = reveal.spinSeconds ?? 3
        let landing = WheelMath.landingRotation(
            segmentCount: DiceWheel.segments.count,
            index: wheelIndex,
            spinSeconds: spinSeconds
        )
        // Rejoining mid-replay: snap to the result, no theatre.
        guard session.caughtUp else {
            rotation = landing
            finished = true
            return
        }
        await WheelMath.animateSpin(
            landing: landing,
            duration: spinSeconds,
            segments: DiceWheel.segments.count
        ) { rotation = $0 }
        finished = true
        SoundPlayer.shared.play(reveal.isSkull ? .lose : (reveal.runOver ? .point : .tick))
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
                Text("+\(die)")
                    .font(Theme.display(52))
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink)
                    .frame(width: 108, height: 96)
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
                    Text(reveal.runOver ? "Next run in \(remaining)s" : "Next spin in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}

/// The pot wheel: five value segments in cyan, two 💀 busts in magenta,
/// spread apart. Rotates via `rotation`; pointer fixed at the top.
struct DiceWheelView: View {
    let rotation: Double

    var body: some View {
        ZStack(alignment: .top) {
            face
                .rotationEffect(.degrees(rotation))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.title2)
                .foregroundStyle(Theme.cyan)
                .shadow(color: Theme.cyan.opacity(0.7), radius: 8)
                .offset(y: -8)
        }
    }

    private var face: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2
            let count = DiceWheel.segments.count
            let segment = 360.0 / Double(count)
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let value = DiceWheel.segments[index]
                    let startDeg = Double(index) * segment - 90
                    let midDeg = startDeg + segment / 2
                    let midRad = midDeg * .pi / 180

                    slice(center: center, radius: radius, startDeg: startDeg, segment: segment)
                        .fill(value == nil ? Theme.magenta.opacity(0.8) : Theme.cyan.opacity(0.22))
                    slice(center: center, radius: radius, startDeg: startDeg, segment: segment)
                        .stroke(Theme.background, lineWidth: 3)

                    Text(value.map { "\($0)" } ?? "💀")
                        .font(Font.custom(Theme.BrandFont.bold, size: 22))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(midDeg + 90))
                        .position(
                            x: center.x + cos(midRad) * radius * 0.66,
                            y: center.y + sin(midRad) * radius * 0.66
                        )
                }
                Circle()
                    .fill(Theme.surface)
                    .frame(width: radius * 0.44, height: radius * 0.44)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    .position(x: center.x, y: center.y)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: radius * 0.32, height: radius * 0.32)
                    .position(x: center.x, y: center.y)
                Circle()
                    .stroke(Theme.hairline, lineWidth: 2)
                    .frame(width: size, height: size)
                    .position(x: center.x, y: center.y)
            }
        }
    }

    private func slice(center: CGPoint, radius: CGFloat, startDeg: Double, segment: Double) -> Path {
        Path { path in
            path.move(to: center)
            path.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(startDeg),
                endAngle: .degrees(startDeg + segment),
                clockwise: false
            )
            path.closeSubpath()
        }
    }
}
