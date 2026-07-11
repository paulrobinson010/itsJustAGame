import SwiftUI

/// One Sense of Direction turn: shows the target place, then gives the
/// player the aiming dial until the shared deadline. The answer locks in
/// either when the player taps "Lock in" or automatically when time runs
/// out. The true bearing is computed from GPS and never shown.
struct DirectionTurnView: View {
    let session: GameSession
    let turnStart: TurnStart

    @State private var bearingGuess: Double = 0
    @State private var compassMode = false
    @State private var submitted = false

    private var location: LocationService { LocationService.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            VStack(spacing: 16) {
                ScoreBar(session: session)
                if context.date < turnStart.introEndsAt {
                    intro(now: context.date)
                } else if !submitted && context.date < turnStart.deadline {
                    aiming(now: context.date)
                } else {
                    waiting
                }
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedAnswer(for: turnStart)
            await autoSubmit()
        }
        .onDisappear {
            location.stopHeadingUpdates()
        }
    }

    private func intro(now: Date) -> some View {
        let remaining = Int(max(0, turnStart.introEndsAt.timeIntervalSince(now)).rounded(.up))
        return VStack(spacing: 20) {
            Spacer()
            Text("Point toward…")
                .font(Theme.subheadline)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            Text(turnStart.target.name)
                .font(Theme.display(34))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text("Get ready — \(remaining)")
                .font(Theme.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func aiming(now: Date) -> some View {
        let remaining = max(0, turnStart.deadline.timeIntervalSince(now))
        let progress = remaining / turnStart.aimSeconds
        return VStack(spacing: 12) {
            Text(turnStart.target.name)
                .font(Theme.headline)
                .lineLimit(1)
                .padding(.horizontal)
            ZStack {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        remaining < 5 ? Color.red : Color.accentColor,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 320, height: 320)
                CompassDial(bearingGuess: $bearingGuess, dialRotation: dialRotation)
                    .frame(width: 290, height: 290)
            }
            Text("\(Int(DirectionMath.normalize(bearingGuess).rounded()))° \(DirectionMath.compassLabel(bearingGuess))")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("\(Int(remaining.rounded(.up))) seconds left")
                .font(Theme.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button {
                    toggleCompassMode()
                } label: {
                    Label(compassMode ? "Compass on" : "Point with phone", systemImage: "safari")
                }
                .buttonStyle(QuietButtonStyle())
                Button {
                    submit()
                } label: {
                    Label("Lock in", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text(submitted
                 ? "Locked in! Waiting for the other players…"
                 : "Time's up! Waiting for the reveal…")
                .font(Theme.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        }
    }

    /// In compass mode the dial rotates so it is aligned with the real
    /// world — pointing the arrow then means physically pointing the phone.
    private var dialRotation: Double {
        guard compassMode, let heading = location.heading else { return 0 }
        return -heading
    }

    private func toggleCompassMode() {
        compassMode.toggle()
        if compassMode {
            location.startHeadingUpdates()
        } else {
            location.stopHeadingUpdates()
        }
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        location.stopHeadingUpdates()
        session.submitAnswer(bearing: DirectionMath.normalize(bearingGuess), for: turnStart)
    }

    private func autoSubmit() async {
        let interval = turnStart.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        if !Task.isCancelled {
            submit()
        }
    }
}

struct CompassDial: View {
    @Binding var bearingGuess: Double
    var dialRotation: Double

    private static let labels = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: size / 2, y: size / 2)
            ZStack {
                dialFace(size: size)
                    .rotationEffect(.degrees(dialRotation))
                Image(systemName: "location.north.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.accentColor)
                    .offset(y: -size * 0.28)
                    .rotationEffect(.degrees(bearingGuess + dialRotation))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let dx = value.location.x - center.x
                        let dy = value.location.y - center.y
                        let screenAngle = atan2(dx, -dy) * 180 / .pi
                        bearingGuess = DirectionMath.normalize(screenAngle - dialRotation)
                    }
            )
        }
    }

    private func dialFace(size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(.secondarySystemBackground))
            Circle().stroke(Theme.hairline, lineWidth: 1)
            ForEach(0..<8, id: \.self) { index in
                Text(Self.labels[index])
                    .font(index % 2 == 0 ? Theme.headline : Theme.caption2)
                    .foregroundStyle(index == 0 ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .offset(y: -size * 0.42)
                    .rotationEffect(.degrees(Double(index) * 45))
            }
        }
    }
}
