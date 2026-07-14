import SwiftUI

/// The shared "get ready" countdown — a big 3-2-1 dead-centre over the game,
/// shown before every turn begins. One consistent look for all games; it
/// renders nothing once the start time has passed.
struct CountdownOverlay: View {
    let startAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let remaining = startAt.timeIntervalSince(context.date)
            if remaining > 0 {
                let count = Int(remaining.rounded(.up))
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    Text("\(count)")
                        .font(.system(size: 130, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .shadow(color: Theme.magenta.opacity(0.7), radius: 24)
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.25), value: count)
                }
                .transition(.opacity)
            }
        }
    }
}
