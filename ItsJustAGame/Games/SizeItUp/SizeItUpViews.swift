import SwiftUI

/// One Size It Up turn: a shape flashes at a target size, then vanishes.
/// You redraw it from memory; the device measures your drawing's size (as a
/// fraction of the square canvas) and closest to the original wins. Measured
/// locally, so latency never matters.
struct SizeTurnView: View {
    let session: GameSession
    let turn: SizeTurn

    @State private var points: [CGPoint] = []
    @State private var submitted = false
    @State private var canvasSide: Double = 300

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let memorizing = phaseIsMemorize(now: now)
            let drawing = phaseIsDraw(now: now)
            VStack(spacing: 14) {
                HigherLowerStatusBar(session: session, alive: session.joinedSlots.sorted(), points: turn.points)
                Text("Turn \(turn.turn) · the \(turn.shape.name)")
                    .font(Theme.kicker)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1.3)
                header(now: now, memorizing: memorizing, drawing: drawing)
                canvas(memorizing: memorizing, drawing: drawing)
                if drawing && !submitted {
                    HStack(spacing: 12) {
                        Button {
                            points = []
                        } label: {
                            Label("Clear", systemImage: "eraser")
                                .font(Theme.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        Button {
                            submit()
                        } label: {
                            Label("Lock it in", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(points.count < 2)
                    }
                    .padding(.horizontal, 24)
                }
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
        }
        .task {
            submitted = session.hasSubmittedSize(for: turn)
            if submitted { return }
            await autoSubmit()
        }
    }

    private func phaseIsMemorize(now: Date) -> Bool {
        now >= turn.startAt && now < turn.drawStart
    }

    private func phaseIsDraw(now: Date) -> Bool {
        !submitted && now >= turn.drawStart && now < turn.deadline
    }

    @ViewBuilder
    private func header(now: Date, memorizing: Bool, drawing: Bool) -> some View {
        if submitted {
            Text("Locked in — waiting…").font(Theme.display(20))
        } else if now < turn.startAt {
            Text("Get ready…").font(Theme.display(24))
        } else if memorizing {
            Text("Memorise the size! 👀").font(Theme.display(24)).foregroundStyle(Theme.magenta)
        } else if drawing {
            let remaining = Int(max(0, turn.deadline.timeIntervalSince(now)).rounded(.up))
            Text("Draw it — same size! · \(remaining)s").font(Theme.display(22)).foregroundStyle(Theme.cyan)
        } else {
            Text("Time's up — waiting…").font(Theme.headline)
        }
    }

    private func canvas(memorizing: Bool, drawing: Bool) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: side / 2, y: side / 2)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.hairline, lineWidth: 1))

                // The shape at its true size — shown while memorising.
                if memorizing {
                    shapePath(turn.shape, side: turn.targetSize * side, center: center)
                        .stroke(Theme.magenta, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                }
                // Simplify: a faint trace of the target left up while drawing.
                if drawing, guideOpacity > 0 {
                    shapePath(turn.shape, side: turn.targetSize * side, center: center)
                        .stroke(Theme.magenta.opacity(guideOpacity), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                }
                // Your drawing.
                strokePath
                    .stroke(session.color(session.mySlot), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard drawing, !submitted else { return }
                        canvasSide = side
                        points.append(value.location)
                    }
            )
            .onAppear { canvasSide = side }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 24)
    }

    private var strokePath: Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        return path
    }

    private func shapePath(_ kind: ShapeKind, side: Double, center: CGPoint) -> Path {
        let half = side / 2
        var path = Path()
        switch kind {
        case .square:
            path.addRect(CGRect(x: center.x - half, y: center.y - half, width: side, height: side))
        case .circle:
            path.addEllipse(in: CGRect(x: center.x - half, y: center.y - half, width: side, height: side))
        case .triangle:
            path.move(to: CGPoint(x: center.x, y: center.y - half))
            path.addLine(to: CGPoint(x: center.x - half, y: center.y + half))
            path.addLine(to: CGPoint(x: center.x + half, y: center.y + half))
            path.closeSubpath()
        case .diamond:
            path.move(to: CGPoint(x: center.x, y: center.y - half))
            path.addLine(to: CGPoint(x: center.x + half, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + half))
            path.addLine(to: CGPoint(x: center.x - half, y: center.y))
            path.closeSubpath()
        }
        return path
    }

    /// How far a shape's drawn size is measured: the larger side of its
    /// bounding box, as a fraction of the canvas.
    private func drawnSizeFraction() -> Double {
        guard points.count >= 2 else { return 0 }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max(), canvasSide > 0 else { return 0 }
        return min(1.0, max(maxX - minX, maxY - minY) / canvasSide)
    }

    private func submit() {
        guard !submitted else { return }
        submitted = true
        // Nothing drawn → let the host record "no drawing" for us.
        guard points.count >= 2 else { return }
        SoundPlayer.shared.play(.lockin)
        session.submitSize(sizePerMille: Int((drawnSizeFraction() * 1000).rounded()), for: turn)
    }

    private func autoSubmit() async {
        let interval = turn.deadline.timeIntervalSinceNow
        if interval > 0 { try? await Task.sleep(for: .seconds(interval)) }
        guard !Task.isCancelled, !submitted else { return }
        submit()
    }

    // MARK: - Simplify

    /// Opacity of the faint target trace left up during drawing (0 = off).
    private var guideOpacity: Double {
        switch session.myAssist {
        case .little: return 0.12
        case .big: return 0.28
        case .cheating: return 0.6
        default: return 0
        }
    }
}

/// Closest to the original size takes the point.
struct SizeRevealView: View {
    let session: GameSession
    let reveal: SizeReveal

    private var targetPerMille: Int { Int((reveal.targetSize * 1000).rounded()) }

    private func error(_ r: SizeResult) -> Int {
        r.sizePerMille.map { abs($0 - targetPerMille) } ?? .max
    }

    var body: some View {
        SensorResultList(
            session: session,
            points: reveal.points,
            kicker: "\(reveal.shape.name) · target \(Int(reveal.targetSize * 100))%",
            headline: reveal.winners.isEmpty
                ? "Nobody drew it…"
                : "📐 \(session.names(reveal.winners)) nailed the size!",
            rows: reveal.results
                .sorted { error($0) < error($1) }
                .map { r in
                    SensorRow(slot: r.slot, winner: reveal.winners.contains(r.slot), badge: "📐",
                              value: r.sizePerMille.map { "\($0 / 10)%" }, empty: "no drawing")
                },
            roundWinners: reveal.roundWinners,
            nextAt: reveal.nextAt,
            nextLabel: "Next shape"
        )
    }
}
