import SwiftUI

enum GridCells {
    /// "A1"…"E5" style labels: letter = row, number = column.
    static func label(_ cell: Int, gridSize: Int) -> String {
        let row = cell / gridSize
        let col = cell % gridSize
        let rowLetter = String(UnicodeScalar(UInt8(65 + min(row, 25))))
        return "\(rowLetter)\(col + 1)"
    }
}

struct CellAppearance {
    var searched = false
    var selected = false
    var isMine = false
    /// The local player's dealt color, used to mark their hiding spot.
    var mineColor: Color = Theme.cyan
    /// Dealt colors of the players revealed on this cell.
    var revealedColors: [Color] = []
}

struct HideSeekGrid: View {
    let gridSize: Int
    let appearance: (Int) -> CellAppearance
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: gridSize),
            spacing: 6
        ) {
            ForEach(0..<(gridSize * gridSize), id: \.self) { cell in
                GridCellView(cell: cell, gridSize: gridSize, appearance: appearance(cell))
                    .onTapGesture { onTap?(cell) }
            }
        }
        .padding(.horizontal)
    }
}

struct GridCellView: View {
    let cell: Int
    let gridSize: Int
    let appearance: CellAppearance

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(background)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if !appearance.revealedColors.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(appearance.revealedColors.indices, id: \.self) { index in
                            Circle()
                                .fill(appearance.revealedColors[index])
                                .frame(width: 10, height: 10)
                                .overlay(Circle().stroke(.white, lineWidth: 1))
                        }
                    }
                } else if appearance.searched {
                    Image(systemName: "xmark")
                        .font(Theme.caption)
                        .foregroundStyle(.tertiary)
                } else if appearance.isMine {
                    Image(systemName: "person.fill")
                        .font(Theme.caption)
                        .foregroundStyle(.white)
                } else {
                    Text(GridCells.label(cell, gridSize: gridSize))
                        .font(Theme.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        appearance.selected ? Color.accentColor : Theme.hairline,
                        lineWidth: appearance.selected ? 2.5 : 1
                    )
            }
    }

    private var background: Color {
        if appearance.isMine { return appearance.mineColor.opacity(0.85) }
        if appearance.searched { return Color.primary.opacity(0.02) }
        return Color.primary.opacity(0.05)
    }
}

/// Player chips for Hide & Seek: run order (when known), found players
/// struck through, the current seeker highlighted.
struct HideSeekStatusBar: View {
    let session: GameSession
    let found: [Int: Int]
    var order: [Int]? = nil
    var seeker: Int? = nil

    private var slots: [Int] {
        order ?? session.joinedSlots.sorted()
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(slots, id: \.self) { slot in
                HStack(spacing: 4) {
                    Circle()
                        .fill(session.color(slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(slot))
                        .font(Theme.caption2)
                        .lineLimit(1)
                        .strikethrough(found[slot] != nil)
                    if found[slot] != nil {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .opacity(found[slot] != nil ? 0.55 : 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.quietFill, in: Capsule())
                .overlay(
                    Capsule().stroke(
                        slot == seeker ? session.color(slot).opacity(0.7) : .clear,
                        lineWidth: 1.5
                    )
                )
            }
        }
        .padding(.horizontal)
    }
}

/// Hiding phase: everyone secretly picks a square before the deadline.
struct HideView: View {
    let session: GameSession
    let hideStart: HideStart

    @State private var selected: Int?
    @State private var submitted = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, hideStart.deadline.timeIntervalSince(context.date))
            VStack(spacing: 16) {
                HideSeekStatusBar(session: session, found: [:])
                Text("Pick your hiding spot!")
                    .font(Theme.display(26))
                Text(submitted
                     ? "Hidden! Waiting for the others…"
                     : "\(Int(remaining.rounded(.up))) seconds to hide — nobody can see your pick")
                    .font(Theme.subheadline)
                    .foregroundStyle(.secondary)
                HideSeekGrid(gridSize: hideStart.gridSize) { cell in
                    CellAppearance(
                        selected: selected == cell && !submitted,
                        isMine: submitted && session.myHideCells[hideStart.round] == cell,
                        mineColor: session.color(session.mySlot)
                    )
                } onTap: { cell in
                    guard !submitted else { return }
                    selected = cell
                }
                Button {
                    if let selected {
                        submit(cell: selected)
                    }
                } label: {
                    Label(
                        selected.map { "Hide at \(GridCells.label($0, gridSize: hideStart.gridSize))" } ?? "Tap a square",
                        systemImage: "eye.slash.fill"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selected == nil || submitted)
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedHide(for: hideStart)
            await autoSubmit()
        }
    }

    private func submit(cell: Int) {
        guard !submitted else { return }
        submitted = true
        session.submitHide(cell: cell, for: hideStart)
    }

    private func autoSubmit() async {
        let interval = hideStart.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted else { return }
        submit(cell: selected ?? Int.random(in: 0..<hideStart.cellCount))
    }
}

/// One seek turn: the seeker picks an unsearched square; everyone else
/// watches the same board.
struct SeekTurnView: View {
    let session: GameSession
    let turnStart: SeekTurnStart

    @State private var selected: Int?
    @State private var submitted = false

    private var isMyTurn: Bool { turnStart.seeker == session.mySlot }
    private var iAmFound: Bool { turnStart.found[session.mySlot] != nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, turnStart.deadline.timeIntervalSince(context.date))
            VStack(spacing: 16) {
                HideSeekStatusBar(session: session, found: turnStart.found, order: turnStart.order, seeker: turnStart.seeker)
                if isMyTurn {
                    Text(submitted ? "Searching…" : "Your turn to seek!")
                        .font(Theme.display(26))
                    Text(submitted
                         ? "Waiting for the reveal…"
                         : "Pick a square to search — \(Int(remaining.rounded(.up)))s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(session.name(turnStart.seeker)) is seeking…")
                        .font(Theme.display(26))
                    Text(iAmFound
                         ? "You've been found — you still get your seek turns."
                         : "Stay hidden! \(Int(remaining.rounded(.up)))s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                }
                HideSeekGrid(gridSize: turnStart.gridSize) { cell in
                    CellAppearance(
                        searched: turnStart.searched.contains(cell),
                        selected: selected == cell && isMyTurn && !submitted,
                        isMine: session.myHideCells[turnStart.round] == cell && !turnStart.searched.contains(cell),
                        mineColor: session.color(session.mySlot),
                        revealedColors: turnStart.found.filter { $0.value == cell }.map(\.key).sorted().map { session.color($0) }
                    )
                } onTap: { cell in
                    guard isMyTurn, !submitted, !turnStart.searched.contains(cell) else { return }
                    selected = cell
                }
                if isMyTurn {
                    Button {
                        if let selected {
                            submit(cell: selected)
                        }
                    } label: {
                        Label(
                            selected.map { "Search \(GridCells.label($0, gridSize: turnStart.gridSize))" } ?? "Tap a square",
                            systemImage: "magnifyingglass"
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selected == nil || submitted)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedSeek(for: turnStart)
            await autoSubmit()
        }
    }

    private func submit(cell: Int) {
        guard !submitted else { return }
        submitted = true
        session.submitSeek(cell: cell, for: turnStart)
    }

    private func autoSubmit() async {
        guard isMyTurn else { return }
        let interval = turnStart.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted, let selected else { return }
        // No selection means the host picks a random square for us.
        submit(cell: selected)
    }
}

/// Result of a search: who (if anyone) was found, and either the next-turn
/// countdown or the round winner.
struct SeekRevealView: View {
    let session: GameSession
    let reveal: SeekReveal

    var body: some View {
        VStack(spacing: 16) {
            HideSeekStatusBar(session: session, found: reveal.found)
            Text(headline)
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            HideSeekGrid(gridSize: reveal.gridSize) { cell in
                CellAppearance(
                    searched: reveal.searched.contains(cell),
                    selected: cell == reveal.cell,
                    isMine: session.myHideCells[reveal.round] == cell && !reveal.searched.contains(cell),
                    mineColor: session.color(session.mySlot),
                    revealedColors: reveal.found.filter { $0.value == cell }.map(\.key).sorted().map { session.color($0) }
                )
            }
            footer
            Spacer()
        }
        .padding(.top, 8)
    }

    private var headline: String {
        let cellLabel = GridCells.label(reveal.cell, gridSize: reveal.gridSize)
        if reveal.revealed.isEmpty {
            return "\(session.name(reveal.seeker)) searched \(cellLabel) — nobody there!"
        }
        let names = reveal.revealed.map { session.name($0) }.joined(separator: " and ")
        return "\(session.name(reveal.seeker)) searched \(cellLabel) — found \(names)!"
    }

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Group {
                if !reveal.roundWinners.isEmpty {
                    Text("🏆 \(session.names(reveal.roundWinners)) \(reveal.roundWinners.count == 1 ? "was" : "were") found last — \(reveal.roundWinners.count == 1 ? "wins" : "they share") the round!")
                        .font(Theme.headline)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                } else if let next = reveal.nextTurnAt {
                    let remaining = Int(max(0, next.timeIntervalSince(context.date)).rounded(.up))
                    Text("Next seeker in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
