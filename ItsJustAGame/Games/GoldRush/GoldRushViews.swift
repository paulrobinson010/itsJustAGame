import SwiftUI

/// One Gold Rush turn: the shared coin board, one secret pick. Alone on a
/// square pockets its coins; sharing one scores nothing for anyone.
struct GoldTurnView: View {
    let session: GameSession
    let turn: GoldTurn

    @State private var selected: Int?
    @State private var submitted = false

    /// Simplify: outline the richest squares so the value spread is
    /// impossible to miss.
    private var hintedCells: Set<Int> {
        guard session.myAssist != nil else { return [] }
        let ranked = turn.coins.enumerated().sorted { $0.element > $1.element }
        return Set(ranked.prefix(3).map(\.offset))
    }

    /// Simplify (levels 2–3): squares someone else has already picked,
    /// appearing live as the host relays them. Locked at the top level.
    private var takenCells: Set<Int> {
        guard let level = session.myAssist, level >= .big else { return [] }
        return Set(turn.assistTaken?[session.mySlot] ?? [])
    }

    private var takenLocked: Bool { session.myAssist == .cheating }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = max(0, turn.deadline.timeIntervalSince(context.date))
            VStack(spacing: 14) {
                DiceStatusBar(session: session, riders: session.joinedSlots.sorted(), banks: turn.totals)
                Text("Turn \(turn.turn) · first to \(GameTiming.goldTarget) coins")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.5)
                Text(submitted ? "Staked — waiting for the others…" : "Pick your square — in secret")
                    .font(Theme.display(22))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                GoldGrid(turnCoins: turn.coins, gridSize: turn.gridSize) { cell in
                    GoldCellState(
                        value: turn.coins[cell],
                        selected: selected == cell && !submitted,
                        hinted: hintedCells.contains(cell) && !submitted,
                        taken: takenCells.contains(cell)
                    )
                } onTap: { cell in
                    guard !submitted else { return }
                    guard !(takenLocked && takenCells.contains(cell)) else { return }
                    selected = cell
                }
                if !submitted {
                    Text(clashCaption)
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(remaining.rounded(.up)))s")
                        .font(Theme.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        if let selected {
                            submit(cell: selected)
                        }
                    } label: {
                        Label(
                            selected.map { "Stake the \(turn.coins[$0])" } ?? "Tap a square",
                            systemImage: "sparkles"
                        )
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selected == nil)
                }
                Spacer()
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedGold(for: turn)
            await autoSubmit()
        }
        .onChange(of: takenCells) { _, taken in
            // A locked square can't stay selected if someone grabs it.
            if takenLocked, let cell = selected, taken.contains(cell) {
                selected = nil
            }
        }
    }

    /// Simplify (levels 2–3): others' picks show up as they land.
    private var clashCaption: String {
        switch session.myAssist {
        case nil, .little:
            return "clash with someone and nobody scores"
        case .big:
            return "squares others take get marked — avoid a clash!"
        case .cheating:
            return "taken squares lock — you can't clash"
        }
    }

    private func submit(cell: Int) {
        guard !submitted else { return }
        submitted = true
        SoundPlayer.shared.play(.lockin)
        session.submitGold(cell: cell, for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 {
            try? await Task.sleep(for: .seconds(interval))
        }
        guard !Task.isCancelled, !submitted, let selected else { return }
        // A tapped-but-unconfirmed square goes in; no pick means sitting out.
        submit(cell: selected)
    }
}

struct GoldCellState {
    var value: Int
    var selected = false
    var clashed = false
    /// Simplify: outlined as one of the richest squares.
    var hinted = false
    /// Simplify (levels 2–3): someone else already picked this square.
    var taken = false
    var pickedColors: [Color] = []
    var won = false
}

/// The coin board. Value tiers get louder colors so the greed is legible
/// at a glance.
struct GoldGrid: View {
    let turnCoins: [Int]
    let gridSize: Int
    let state: (Int) -> GoldCellState
    var onTap: ((Int) -> Void)? = nil

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: gridSize),
            spacing: 6
        ) {
            ForEach(0..<(gridSize * gridSize), id: \.self) { cell in
                GoldCellView(state: state(cell))
                    .onTapGesture { onTap?(cell) }
            }
        }
        .padding(.horizontal)
    }
}

struct GoldCellView: View {
    let state: GoldCellState

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.quietFill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                VStack(spacing: 2) {
                    Text("\(state.value)")
                        .font(Font.custom(Theme.BrandFont.semiBold, size: 16))
                        .monospacedDigit()
                        .foregroundStyle(valueColor)
                        .opacity(state.clashed || state.taken ? 0.35 : 1)
                    if state.clashed {
                        Text("💥")
                            .font(.system(size: 12))
                    } else if state.taken {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if !state.pickedColors.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(state.pickedColors.indices, id: \.self) { index in
                                Circle()
                                    .fill(state.pickedColors[index])
                                    .frame(width: 8, height: 8)
                                    .overlay(Circle().stroke(.white, lineWidth: 1))
                            }
                        }
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        strokeColor,
                        lineWidth: state.selected || state.won || state.clashed ? 2.5 : (state.hinted ? 1.8 : 1)
                    )
            }
    }

    private var valueColor: Color {
        if state.value >= 8 { return Theme.magenta }
        if state.value >= 5 { return Theme.cyan }
        return .white.opacity(0.75)
    }

    private var strokeColor: Color {
        if state.clashed { return Theme.magenta }
        if state.won { return Theme.cyan }
        if state.selected { return Color.accentColor }
        if state.hinted { return Theme.cyan.opacity(0.45) }
        return Theme.hairline
    }
}

/// The reveal: everyone's pick on the board, clashes burned, coins pocketed.
struct GoldRevealView: View {
    let session: GameSession
    let reveal: GoldReveal

    var body: some View {
        VStack(spacing: 14) {
            DiceStatusBar(session: session, riders: session.joinedSlots.sorted(), banks: reveal.totals)
            Text("Turn \(reveal.turn)")
                .font(Theme.kicker)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1.5)
            Text(headline)
                .font(Theme.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            GoldGrid(turnCoins: reveal.coins, gridSize: reveal.gridSize) { cell in
                GoldCellState(
                    value: reveal.coins[cell],
                    clashed: reveal.clashes.contains(cell),
                    pickedColors: reveal.picks
                        .filter { $0.value == cell }
                        .map(\.key)
                        .sorted()
                        .map { session.color($0) },
                    won: reveal.picks.contains { $0.value == cell } && !reveal.clashes.contains(cell)
                )
            }
            gainsList
            footer
            Spacer()
        }
        .padding(.top, 8)
    }

    private var headline: String {
        let clashedSlots = reveal.picks
            .filter { reveal.clashes.contains($0.value) }
            .map(\.key)
            .sorted()
        if !clashedSlots.isEmpty {
            return "💥 \(session.names(clashedSlots)) wanted the same gold!"
        }
        if reveal.gains.isEmpty {
            return "Nobody staked a claim…"
        }
        return "Everyone struck gold!"
    }

    private var gainsList: some View {
        VStack(spacing: 6) {
            ForEach(session.joinedSlots.sorted(), id: \.self) { slot in
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.color(slot))
                        .frame(width: 8, height: 8)
                    Text(session.name(slot))
                        .font(Theme.subheadline)
                        .lineLimit(1)
                    Spacer()
                    if let gain = reveal.gains[slot] {
                        Text("+\(gain)")
                            .font(Theme.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.cyan)
                    } else if reveal.picks[slot] != nil {
                        Text("💥 0")
                            .font(Theme.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.magenta)
                    } else {
                        Text("no pick")
                            .font(Theme.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
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
                    Text("Fresh board in \(remaining)s")
                        .font(Theme.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(" ")
                }
            }
        }
    }
}
