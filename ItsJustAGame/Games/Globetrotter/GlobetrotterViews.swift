import MapKit
import SwiftUI

/// A frozen satellite view of the whole planet — continents by shape, no
/// place labels to give it away. Shared by the turn and reveal screens.
private enum Globe {
    static let worldRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 5),
        span: MKCoordinateSpan(latitudeDelta: 132, longitudeDelta: 340)
    )

    static func distanceText(_ km: Double) -> String {
        let n = Int(km.rounded())
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: n)) ?? "\(n)") + " km"
    }
}

/// The guessing phase: a bare world map and a famous landmark to place.
/// Tap to drop your pin anywhere on Earth, adjust freely, lock it in.
struct GlobeTurnView: View {
    let session: GameSession
    let turn: GlobeTurn

    @State private var guess: Coordinate?
    @State private var submitted = false

    private struct Pin: Identifiable {
        let id = 0
        let coordinate: CLLocationCoordinate2D
    }

    private var hint: FingerHint? {
        turn.assistHints?[session.mySlot]
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, turn.deadline.timeIntervalSince(context.date))
            VStack(spacing: 12) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Where in the world?")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text(turn.landmark)
                    .font(Theme.display(26))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                mapView
                    .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
                    .padding(.horizontal)
                if submitted {
                    Text("Locked in — waiting for the others…")
                        .font(Theme.headline)
                } else if remaining <= 0 {
                    Text("Time's up — waiting for the reveal…")
                        .font(Theme.headline)
                } else {
                    Text(guessCaption(remaining: Int(remaining.rounded(.up))))
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    Button {
                        submit()
                    } label: {
                        Label("Lock it in", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(guess == nil)
                }
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedGlobe(for: turn)
            await autoSubmit()
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            // Frozen on purpose: a tap is your answer, and everyone sees
            // the same view.
            Map(initialPosition: .region(Globe.worldRegion), interactionModes: []) {
                if let hint {
                    MapCircle(center: hint.center.clCoordinate, radius: hint.radiusKm * 1000)
                        .foregroundStyle(Theme.cyan.opacity(0.12))
                        .stroke(Theme.cyan.opacity(0.55), style: StrokeStyle(lineWidth: 2))
                }
                ForEach(pins) { pin in
                    Annotation("", coordinate: pin.coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(session.color(session.mySlot))
                            .shadow(color: session.color(session.mySlot).opacity(0.7), radius: 8)
                    }
                }
            }
            .mapStyle(.imagery)
            .onTapGesture { point in
                guard !submitted else { return }
                if let coordinate = proxy.convert(point, from: .local) {
                    guess = Coordinate(coordinate)
                }
            }
        }
    }

    private func guessCaption(remaining: Int) -> String {
        guard hint != nil else {
            return "\(remaining)s — tap the map to drop your pin"
        }
        // Simplify level 1 also names the continent; higher levels just get
        // a tighter circle.
        if session.myAssist == .little {
            return "\(remaining)s — it's in \(turn.continent), inside the circle"
        }
        return "\(remaining)s — it's somewhere in the glowing circle"
    }

    private var pins: [Pin] {
        guard let guess else { return [] }
        return [Pin(coordinate: guess.clCoordinate)]
    }

    private func submit() {
        guard !submitted, let guess else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitGlobe(coordinate: guess, for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        submit()
    }
}

/// The reveal: the landmark starred on the map, everyone's pin, distances
/// ranked closest first.
struct GlobeRevealView: View {
    let session: GameSession
    let reveal: GlobeReveal

    var body: some View {
        VStack(spacing: 12) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text("\(reveal.landmark) — \(reveal.country)")
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(headline)
                .font(Theme.headline)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            revealMap
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                .padding(.horizontal)
            resultsList
            footer
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var headline: String {
        if reveal.winners.isEmpty {
            return "Nobody dropped a pin…"
        }
        return "🌍 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!"
    }

    private var placedOutcomes: [FingerOutcome] {
        reveal.outcomes.filter { $0.coordinate != nil }
    }

    private struct GuessLine: Identifiable {
        let id: Int
        let start: CLLocationCoordinate2D
        let color: Color
    }

    private var guessLines: [GuessLine] {
        placedOutcomes.compactMap { outcome in
            guard let coordinate = outcome.coordinate else { return nil }
            return GuessLine(id: outcome.slot, start: coordinate.clCoordinate, color: session.color(outcome.slot))
        }
    }

    private func pinLabel(for outcome: FingerOutcome) -> String {
        if let km = outcome.distanceKm {
            return "\(session.name(outcome.slot)) · \(Globe.distanceText(km))"
        }
        return session.name(outcome.slot)
    }

    private var revealMap: some View {
        Map(initialPosition: .region(fitRegion)) {
            ForEach(guessLines) { line in
                MapPolyline(coordinates: [line.start, reveal.target.clCoordinate])
                    .stroke(line.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [6, 6]))
            }
            Marker(reveal.landmark, systemImage: "star.fill", coordinate: reveal.target.clCoordinate)
                .tint(.yellow)
            ForEach(placedOutcomes) { outcome in
                Annotation(pinLabel(for: outcome), coordinate: outcome.coordinate!.clCoordinate) {
                    Circle()
                        .fill(session.color(outcome.slot))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.imagery)
    }

    private var fitRegion: MKCoordinateRegion {
        var points = [reveal.target]
        points.append(contentsOf: placedOutcomes.compactMap(\.coordinate))
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return Globe.worldRegion
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLat - minLat) * 1.5, 12), 150),
            longitudeDelta: min(max((maxLon - minLon) * 1.5, 12), 340)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var resultsList: some View {
        VStack(spacing: 6) {
            ForEach(sortedOutcomes) { outcome in
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.color(outcome.slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(outcome.slot))
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    if reveal.winners.contains(outcome.slot) {
                        Text("🌍")
                    }
                    Spacer()
                    if let km = outcome.distanceKm {
                        Text(Globe.distanceText(km))
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                    } else {
                        Text("no pin")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
    }

    private var sortedOutcomes: [FingerOutcome] {
        reveal.outcomes.sorted { ($0.distanceKm ?? .infinity) < ($1.distanceKm ?? .infinity) }
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
                    Text("Next landmark in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
