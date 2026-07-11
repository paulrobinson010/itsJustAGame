import MapKit
import SwiftUI

/// The guessing phase: a bare satellite map (no place names) and a place
/// to find. Tap to drop your pin, adjust as often as you like, lock it in.
struct FingerTurnView: View {
    let session: GameSession
    let turn: FingerTurn

    @State private var guess: Coordinate?
    @State private var submitted = false

    private struct Pin: Identifiable {
        let id = 0
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, turn.deadline.timeIntervalSince(context.date))
            VStack(spacing: 12) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text(turn.regionName)
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text("Where is \(turn.placeName)?")
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
                    Text("\(Int(remaining.rounded(.up)))s — tap the map to drop your pin")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
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
            submitted = session.hasSubmittedFinger(for: turn)
            await autoSubmit()
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(initialPosition: .region(initialRegion), interactionModes: [.pan, .zoom]) {
                ForEach(pins) { pin in
                    Annotation("", coordinate: pin.coordinate) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.cyan)
                            .shadow(color: Theme.cyan.opacity(0.7), radius: 8)
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

    private var pins: [Pin] {
        guard let guess else { return [] }
        return [Pin(coordinate: guess.clCoordinate)]
    }

    private var initialRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: turn.regionCenter.clCoordinate,
            span: MKCoordinateSpan(latitudeDelta: turn.regionSpanLat, longitudeDelta: turn.regionSpanLon)
        )
    }

    private func submit() {
        guard !submitted, let guess else { return }
        submitted = true
        session.submitFinger(coordinate: guess, for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        // Submit a placed-but-unconfirmed pin; no pin means no answer.
        submit()
    }
}

/// The reveal: the capital starred, everyone's pin, distances ranked.
struct FingerRevealView: View {
    let session: GameSession
    let reveal: FingerReveal

    var body: some View {
        VStack(spacing: 12) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: reveal.points)
            Text("\(reveal.placeName) — \(reveal.capitalName)")
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
            return "Nobody placed a pin…"
        }
        return "🎯 \(session.names(reveal.winners)) \(reveal.winners.count == 1 ? "was" : "were") closest!"
    }

    private var placedOutcomes: [FingerOutcome] {
        reveal.outcomes.filter { $0.coordinate != nil }
    }

    private var revealMap: some View {
        Map(initialPosition: .region(fitRegion)) {
            Marker(reveal.capitalName, systemImage: "star.fill", coordinate: reveal.target.clCoordinate)
                .tint(.yellow)
            ForEach(placedOutcomes) { outcome in
                Annotation(session.name(outcome.slot), coordinate: outcome.coordinate!.clCoordinate) {
                    Circle()
                        .fill(PlayerStyle.color(for: outcome.slot))
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
            return MKCoordinateRegion(
                center: reveal.target.clCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            )
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: min(max((maxLat - minLat) * 1.6, 4), 160),
            longitudeDelta: min(max((maxLon - minLon) * 1.6, 4), 340)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    private var resultsList: some View {
        VStack(spacing: 6) {
            ForEach(sortedOutcomes) { outcome in
                HStack(spacing: 8) {
                    Circle()
                        .fill(PlayerStyle.color(for: outcome.slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(outcome.slot))
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    if reveal.winners.contains(outcome.slot) {
                        Text("🎯")
                    }
                    Spacer()
                    if let km = outcome.distanceKm {
                        Text("\(Int(km.rounded())) km")
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
                    Text("Next place in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
