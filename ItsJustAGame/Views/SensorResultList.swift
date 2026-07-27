import SwiftUI

/// A row in a sensor-game reveal: a player, their value (or an "empty"
/// note), and a winner badge.
struct SensorRow: Identifiable {
    let slot: Int
    let winner: Bool
    let badge: String
    /// Formatted value, or nil to show `empty`.
    let value: String?
    let empty: String
    var id: Int { slot }
}

/// Shared reveal layout for the sensor games (Loudest, Blow It Out,
/// Hum It, …): the score bar, a headline, a ranked list, and the
/// round/next footer — so each game's reveal is a few lines.
struct SensorResultList: View {
    let session: GameSession
    let points: [Int: Int]
    let kicker: String
    let headline: String
    let rows: [SensorRow]
    let roundWinners: [Int]
    let nextAt: Date?
    let nextLabel: String

    var body: some View {
        VStack(spacing: 14) {
            HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: points)
            Text(kicker)
                .font(Theme.kicker)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            Text(headline)
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    HStack(spacing: 8) {
                        Circle().fill(session.color(row.slot)).frame(width: 8, height: 8)
                        Text(session.name(row.slot)).font(Theme.subheadline).lineLimit(1)
                        if row.winner { Text(row.badge) }
                        Spacer()
                        if let value = row.value {
                            Text(value)
                                .font(Theme.subheadline.weight(.semibold))
                                .monospacedDigit()
                        } else {
                            Text(row.empty)
                                .font(Theme.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .card()
            .padding(.horizontal, 24)
            footer
            Spacer()
        }
        .padding(.top, 8)
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if !roundWinners.isEmpty {
                    Text("🏆 \(session.names(roundWinners)) \(roundWinners.count == 1 ? "wins" : "win") the round!")
                        .font(Theme.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let next = nextAt {
                    let remaining = Int(max(0, next.timeIntervalSince(context.date)).rounded(.up))
                    Text("\(nextLabel) in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
