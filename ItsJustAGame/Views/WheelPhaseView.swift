import SwiftUI

/// The spinning wheel that picks who chooses the round's game. The result
/// was already decided by the host device — the wheel just animates to land
/// on it.
struct WheelPhaseView: View {
    let session: GameSession
    let round: Int
    let chooser: Int

    @State private var rotation: Double = 0
    @State private var finished = false
    @State private var hasChosen = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Round \(round)")
                .font(.title2.bold())
            Text("Who picks the game?")
                .foregroundStyle(.secondary)

            ZStack(alignment: .top) {
                WheelShapeView(players: session.players)
                    .rotationEffect(.degrees(rotation))
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.title)
                    .offset(y: -10)
            }
            .frame(width: 300, height: 300)
            .padding(.top, 12)

            Group {
                if !finished {
                    Text("Spinning…")
                        .foregroundStyle(.secondary)
                } else if chooser == session.mySlot {
                    VStack(spacing: 12) {
                        Text("You pick the game!")
                            .font(.headline)
                        ForEach(MiniGameType.allCases, id: \.self) { game in
                            let available = session.joinedSlots.count >= game.minPlayers
                            Button {
                                hasChosen = true
                                session.submitChoice(round: round, game: game)
                            } label: {
                                VStack(spacing: 2) {
                                    Label(game.displayName, systemImage: "location.north.circle.fill")
                                    if !available {
                                        Text("Needs at least \(game.minPlayers) players")
                                            .font(.caption2)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(hasChosen || !available)
                        }
                        if hasChosen {
                            Text("Starting…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 32)
                } else {
                    Text("\(session.name(chooser)) is picking the game…")
                        .font(.headline)
                }
            }
            .frame(minHeight: 120)

            Spacer()
        }
        .padding(.top, 24)
        .onAppear { spin() }
    }

    private func spin() {
        let players = session.players
        guard let index = players.firstIndex(where: { $0.slot == chooser }), players.count > 0 else {
            finished = true
            return
        }
        let segment = 360.0 / Double(players.count)
        let landing = 360.0 * 6 - (Double(index) + 0.5) * segment
        withAnimation(.easeOut(duration: GameTiming.wheelSpinSeconds)) {
            rotation = landing
        }
        Task {
            try? await Task.sleep(for: .seconds(GameTiming.wheelSpinSeconds + 0.3))
            finished = true
        }
    }
}

struct WheelShapeView: View {
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
                    let start = Double(index) * segment - 90
                    let middle = (start + segment / 2) * .pi / 180
                    Path { path in
                        path.move(to: center)
                        path.addArc(
                            center: center,
                            radius: radius,
                            startAngle: .degrees(start),
                            endAngle: .degrees(start + segment),
                            clockwise: false
                        )
                        path.closeSubpath()
                    }
                    .fill(PlayerStyle.color(for: player.slot).opacity(0.85))

                    Text(player.name)
                        .font(.footnote.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(width: radius * 0.8)
                        .position(
                            x: center.x + cos(middle) * radius * 0.6,
                            y: center.y + sin(middle) * radius * 0.6
                        )
                }
                Circle()
                    .stroke(.primary.opacity(0.2), lineWidth: 3)
                    .frame(width: size, height: size)
                    .position(center)
            }
        }
    }
}
