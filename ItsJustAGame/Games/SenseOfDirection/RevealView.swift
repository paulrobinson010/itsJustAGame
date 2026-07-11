import MapKit
import SwiftUI

/// The end-of-turn reveal: everyone's location, the target, and each
/// player's guess drawn as a ray — a perfect guess ends exactly on the
/// target.
struct RevealView: View {
    let session: GameSession
    let reveal: TurnReveal

    var body: some View {
        VStack(spacing: 12) {
            ScoreBar(session: session)

            Group {
                if let winner = reveal.winner {
                    Text("🎯 \(session.name(winner)) takes the point!")
                } else {
                    Text("No one scored this time…")
                }
            }
            .font(.headline)

            RevealMap(session: session, reveal: reveal)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

            resultsList

            footer
        }
        .padding(.vertical, 8)
    }

    private var resultsList: some View {
        VStack(spacing: 6) {
            ForEach(sortedOutcomes) { outcome in
                HStack {
                    Circle()
                        .fill(PlayerStyle.color(for: outcome.slot))
                        .frame(width: 10, height: 10)
                    Text(session.name(outcome.slot))
                        .lineLimit(1)
                    if outcome.slot == reveal.winner {
                        Text("🎯")
                    }
                    Spacer()
                    if let error = outcome.errorDegrees {
                        Text("\(Int(error.rounded()))° off")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    } else {
                        Text("no answer")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
        .padding(.horizontal, 24)
    }

    private var sortedOutcomes: [PlayerOutcome] {
        reveal.outcomes.sorted { ($0.errorDegrees ?? 999) < ($1.errorDegrees ?? 999) }
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if let winner = reveal.roundWinner {
                    Text("🏆 \(session.name(winner)) wins the round!")
                        .font(.headline)
                } else if let next = reveal.nextTurnAt {
                    let remaining = Int(max(0, next.timeIntervalSince(context.date)).rounded(.up))
                    Text("Next place in \(remaining)s")
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}

struct RevealMap: View {
    let session: GameSession
    let reveal: TurnReveal

    private struct GuessRay: Identifiable {
        let id: Int
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
        let color: Color
    }

    var body: some View {
        Map(initialPosition: .region(region)) {
            Marker(reveal.target.name, systemImage: "star.fill", coordinate: reveal.target.coordinate.clCoordinate)
                .tint(.yellow)
            ForEach(placedOutcomes) { outcome in
                Annotation(session.name(outcome.slot), coordinate: outcome.coordinate!.clCoordinate) {
                    Circle()
                        .fill(PlayerStyle.color(for: outcome.slot))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            ForEach(guessRays) { ray in
                MapPolyline(coordinates: [ray.start, ray.end])
                    .stroke(ray.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .mapStyle(.standard(elevation: .flat))
    }

    private var placedOutcomes: [PlayerOutcome] {
        reveal.outcomes.filter { $0.coordinate != nil }
    }

    private var guessRays: [GuessRay] {
        placedOutcomes.compactMap { outcome in
            guard let start = outcome.coordinate, let bearing = outcome.bearing else { return nil }
            let distance = DirectionMath.distanceMeters(from: start, to: reveal.target.coordinate)
            let end = DirectionMath.destination(from: start, bearing: bearing, distanceMeters: distance)
            return GuessRay(
                id: outcome.slot,
                start: start.clCoordinate,
                end: end.clCoordinate,
                color: PlayerStyle.color(for: outcome.slot)
            )
        }
    }

    private var region: MKCoordinateRegion {
        var points = [reveal.target.coordinate]
        points.append(contentsOf: placedOutcomes.compactMap(\.coordinate))
        for ray in guessRays {
            points.append(Coordinate(ray.end))
        }
        let lats = points.map(\.latitude)
        let lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(
                center: reveal.target.coordinate.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
            )
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLat - minLat) * 1.6, 0.05), 160),
            longitudeDelta: min(max((maxLon - minLon) * 1.6, 0.05), 340)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
