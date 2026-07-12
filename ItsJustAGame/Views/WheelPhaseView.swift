import SwiftUI

/// The spinning wheel that picks who chooses the round's game. The result
/// and the spin length (3–10s, host-rolled) were already decided — the
/// wheel just animates to land on them, identically on every device.
struct WheelPhaseView: View {
    let session: GameSession
    let round: Int
    let chooser: Int
    let spinSeconds: Double

    @State private var rotation: Double = 0
    @State private var finished = false
    @State private var hasChosen = false

    var body: some View {
        // Scrolls because the chooser lists every mini game.
        ScrollView {
            VStack(spacing: 24) {
                Text("Round \(round)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text("Who picks the game?")
                    .font(Theme.display(28))

                SpinningWheel(players: session.players, rotation: rotation, pointerColor: Theme.cyan)
                    .frame(width: 310, height: 310)
                    .padding(.top, 8)

                Group {
                    if !finished {
                        Text("Spinning…")
                            .font(Theme.subheadline)
                            .foregroundStyle(.secondary)
                    } else if chooser == session.mySlot {
                        VStack(spacing: 12) {
                            Text("You pick the game!")
                                .font(Theme.headline)
                            ForEach(MiniGameType.allCases, id: \.self) { game in
                                let available = session.joinedSlots.count >= game.minPlayers
                                Button {
                                    hasChosen = true
                                    session.submitChoice(round: round, game: game)
                                } label: {
                                    VStack(spacing: 2) {
                                        Label(game.displayName, systemImage: game.iconName)
                                        if !available {
                                            Text("Needs at least \(game.minPlayers) players")
                                                .font(Theme.caption2)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(hasChosen || !available)
                            }
                            if hasChosen {
                                Text("Starting…")
                                    .font(Theme.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 32)
                    } else {
                        Text("\(session.name(chooser)) is picking the game…")
                            .font(Theme.headline)
                    }
                }
                .frame(minHeight: 120)
            }
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .onAppear { spin() }
    }

    private func spin() {
        guard let landing = WheelMath.landingRotation(
            players: session.players,
            target: chooser,
            spinSeconds: spinSeconds
        ) else {
            finished = true
            return
        }
        // Rejoining mid-replay: snap to the result, no theatre.
        guard session.caughtUp else {
            rotation = landing
            finished = true
            return
        }
        Task {
            await WheelMath.animateSpin(
                landing: landing,
                duration: spinSeconds,
                segments: session.players.count
            ) { rotation = $0 }
            finished = true
            SoundPlayer.shared.play(.point)
        }
    }
}

enum WheelMath {
    /// Whole turns plus the offset that parks the target segment under the
    /// pointer. Longer spins get more turns but stay slow and cinematic.
    static func landingRotation(players: [PlayerInfo], target: Int, spinSeconds: Double) -> Double? {
        guard !players.isEmpty,
              let index = players.firstIndex(where: { $0.slot == target }) else { return nil }
        let segment = 360.0 / Double(players.count)
        let turns = (2.0 + spinSeconds * 0.5).rounded()
        return 360.0 * turns - (Double(index) + 0.5) * segment
    }

    /// Drives the rotation frame by frame with a long deceleration, and
    /// clicks whenever a segment boundary passes the pointer — so the
    /// clicks slow down exactly as the wheel does.
    static func animateSpin(
        landing: Double,
        duration: Double,
        segments: Int,
        update: @MainActor (Double) -> Void
    ) async {
        let segmentAngle = 360.0 / Double(max(segments, 1))
        let start = Date()
        var lastClick = 0
        while !Task.isCancelled {
            let x = min(1.0, Date().timeIntervalSince(start) / duration)
            let eased = 1 - pow(1 - x, 3.0)
            let rotation = landing * eased
            await update(rotation)
            let clickIndex = Int(rotation / segmentAngle)
            if clickIndex > lastClick {
                lastClick = clickIndex
                SoundPlayer.shared.play(.tick)
            }
            if x >= 1 { break }
            try? await Task.sleep(for: .seconds(1.0 / 60.0))
        }
        await update(landing)
    }
}

/// The wheel with its pointer. Rotate via `rotation`.
struct SpinningWheel: View {
    let players: [PlayerInfo]
    let rotation: Double
    var pointerColor: Color = Theme.cyan

    var body: some View {
        ZStack(alignment: .top) {
            WheelFace(players: players)
                .rotationEffect(.degrees(rotation))
            Image(systemName: "arrowtriangle.down.fill")
                .font(.title)
                .foregroundStyle(pointerColor)
                .shadow(color: pointerColor.opacity(0.7), radius: 8)
                .offset(y: -10)
        }
    }
}

/// Player-colored segments split by hairlines, radial name pills reading
/// from the middle out, and a dark hub wearing the logo.
struct WheelFace: View {
    let players: [PlayerInfo]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            let radius = size / 2
            let segment = 360.0 / Double(max(players.count, 1))
            ZStack {
                ForEach(players.indices, id: \.self) { index in
                    let player = players[index]
                    let startDeg = Double(index) * segment - 90
                    let midDeg = startDeg + segment / 2
                    let midRad = midDeg * .pi / 180

                    segmentPath(center: center, radius: radius, startDeg: startDeg, segment: segment)
                        .fill(player.color.opacity(0.82))
                    segmentPath(center: center, radius: radius, startDeg: startDeg, segment: segment)
                        .stroke(Theme.background, lineWidth: 3)

                    Text(player.name)
                        .font(Font.custom(Theme.BrandFont.medium, size: 12))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: radius * 0.5)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.ink.opacity(0.65), in: Capsule())
                        .rotationEffect(.degrees(midDeg))
                        .position(
                            x: center.x + cos(midRad) * radius * 0.6,
                            y: center.y + sin(midRad) * radius * 0.6
                        )
                }
                Circle()
                    .fill(Theme.surface)
                    .frame(width: radius * 0.46, height: radius * 0.46)
                    .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
                    .position(x: center.x, y: center.y)
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: radius * 0.34, height: radius * 0.34)
                    .position(x: center.x, y: center.y)
                Circle()
                    .stroke(Theme.hairline, lineWidth: 2)
                    .frame(width: size, height: size)
                    .position(x: center.x, y: center.y)
            }
        }
    }

    private func segmentPath(center: CGPoint, radius: CGFloat, startDeg: Double, segment: Double) -> Path {
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

/// Several players reached the winning round count together — a wheel of
/// just the tied players spins and lands on the host-rolled random winner.
struct TieBreakView: View {
    let session: GameSession
    let candidates: [Int]
    let winner: Int
    let spinSeconds: Double

    @State private var rotation: Double = 0
    @State private var finished = false

    private var candidatePlayers: [PlayerInfo] {
        candidates.compactMap { session.config?.player($0) }
    }

    var body: some View {
        VStack(spacing: 24) {
            Text("Tie-breaker")
                .font(Theme.kicker)
                .foregroundStyle(Theme.magenta)
                .textCase(.uppercase)
                .kerning(1.5)
            Text("\(session.names(candidates)) all hit \(session.config?.roundsToWin ?? 0) rounds!")
                .font(Theme.display(24))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("The wheel decides — totally at random.")
                .font(Theme.subheadline)
                .foregroundStyle(.secondary)

            SpinningWheel(players: candidatePlayers, rotation: rotation, pointerColor: Theme.magenta)
                .frame(width: 310, height: 310)
                .padding(.top, 8)

            Text(finished ? "🎉 \(session.name(winner)) takes the game!" : "Spinning…")
                .font(Theme.headline)
            Spacer()
        }
        .padding(.top, 24)
        .onAppear { spin() }
    }

    private func spin() {
        guard let landing = WheelMath.landingRotation(
            players: candidatePlayers,
            target: winner,
            spinSeconds: spinSeconds
        ) else {
            finished = true
            return
        }
        guard session.caughtUp else {
            rotation = landing
            finished = true
            return
        }
        Task {
            SoundPlayer.shared.startDrumroll()
            await WheelMath.animateSpin(
                landing: landing,
                duration: spinSeconds,
                segments: candidatePlayers.count
            ) { rotation = $0 }
            SoundPlayer.shared.stopDrumroll()
            finished = true
            SoundPlayer.shared.play(.fanfare)
        }
    }
}
