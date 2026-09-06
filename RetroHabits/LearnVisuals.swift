import SwiftUI

/// Procedurally drawn comic-style illustrations for LEARN cards.
/// Drawn rather than bundled so they stay sharp at any size and never
/// repeat identically — each card seeds its own variation.
struct LearnIllustration: View {
    let visual: LearnVisual
    let color: Color
    var seed: Int = 0

    var body: some View {
        ZStack {
            // Halftone dot field behind everything.
            HalftoneField(color: color.opacity(0.28))

            switch visual {
            case .pipeline: PipelineArt(color: color)
            case .attention: AttentionArt(color: color, seed: seed)
            case .vectors: VectorArt(color: color, seed: seed)
            case .stack: StackArt(color: color)
            case .network: NetworkArt(color: color, seed: seed)
            case .curve: CurveArt(color: color)
            case .tokens: TokenArt(color: color, seed: seed)
            case .cluster: ClusterArt(color: color, seed: seed)
            }
        }
        .drawingGroup()
    }
}

// MARK: - Backing texture

private struct HalftoneField: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 13
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    // Dots grow toward the bottom-right for a printed-ink feel.
                    let t = (x / size.width + y / size.height) / 2
                    let radius = 0.8 + t * 2.2
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius)),
                        with: .color(color)
                    )
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

// MARK: - Pieces

private struct PipelineArt: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let boxW = w * 0.2
            let boxH = h * 0.26
            let y = h / 2 - boxH / 2
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    let x = w * (0.08 + Double(index) * 0.31)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(index == 1 ? color : Color.white)
                        .frame(width: boxW, height: boxH)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Comic.ink, lineWidth: 3))
                        .position(x: x + boxW / 2, y: y + boxH / 2)
                }
                ForEach(0..<2, id: \.self) { index in
                    let startX = w * (0.08 + Double(index) * 0.31) + boxW
                    Arrow()
                        .stroke(Comic.ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        .frame(width: w * 0.11, height: 16)
                        .position(x: startX + w * 0.055, y: h / 2)
                }
            }
        }
    }
}

private struct Arrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.move(to: CGPoint(x: rect.maxX - rect.height * 0.5, y: rect.midY - rect.height * 0.4))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - rect.height * 0.5, y: rect.midY + rect.height * 0.4))
        return path
    }
}

private struct AttentionArt: View {
    let color: Color
    let seed: Int

    var body: some View {
        GeometryReader { geo in
            let side: CGFloat = min(geo.size.width, geo.size.height) * 0.72
            let cells = 6
            let cell: CGFloat = side / CGFloat(cells)
            let originX: CGFloat = (geo.size.width - side) / 2
            let originY: CGFloat = (geo.size.height - side) / 2
            var generator = SeededGenerator(seed: seed)
            let weights: [Double] = (0..<(cells * cells)).map { _ in Double.random(in: 0...1, using: &generator) }

            ZStack {
                ForEach(0..<(cells * cells), id: \.self) { index in
                    let row = index / cells
                    let col = index % cells
                    Rectangle()
                        .fill(color.opacity(0.15 + weights[index] * 0.85))
                        .frame(width: cell - 2, height: cell - 2)
                        .overlay(Rectangle().stroke(Comic.ink.opacity(0.4), lineWidth: 1))
                        .position(
                            x: originX + cell * (CGFloat(col) + 0.5),
                            y: originY + cell * (CGFloat(row) + 0.5)
                        )
                }
                Rectangle()
                    .stroke(Comic.ink, lineWidth: 3)
                    .frame(width: side, height: side)
            }
        }
    }
}

private struct VectorArt: View {
    let color: Color
    let seed: Int

    var body: some View {
        GeometryReader { geo in
            var generator = SeededGenerator(seed: seed)
            let width: CGFloat = geo.size.width
            let height: CGFloat = geo.size.height
            let points: [CGPoint] = (0..<16).map { _ -> CGPoint in
                let fx: CGFloat = CGFloat(Double.random(in: 0.12...0.88, using: &generator))
                let fy: CGFloat = CGFloat(Double.random(in: 0.15...0.85, using: &generator))
                return CGPoint(x: fx * width, y: fy * height)
            }
            let origin = CGPoint(x: geo.size.width * 0.12, y: geo.size.height * 0.85)

            ZStack {
                // Axes
                Path { path in
                    path.move(to: CGPoint(x: origin.x, y: geo.size.height * 0.12))
                    path.addLine(to: origin)
                    path.addLine(to: CGPoint(x: geo.size.width * 0.9, y: origin.y))
                }
                .stroke(Comic.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                ForEach(0..<points.count, id: \.self) { index in
                    Circle()
                        .fill(index % 3 == 0 ? color : Color.white)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(Comic.ink, lineWidth: 2.5))
                        .position(points[index])
                }
            }
        }
    }
}

private struct StackArt: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let count = 5
            let slabH = geo.size.height * 0.11
            ZStack {
                ForEach(0..<count, id: \.self) { index in
                    let inset = CGFloat(index) * geo.size.width * 0.035
                    RoundedRectangle(cornerRadius: 5)
                        .fill(index.isMultiple(of: 2) ? color.opacity(0.85) : Color.white)
                        .frame(width: geo.size.width * 0.62 - inset, height: slabH)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Comic.ink, lineWidth: 3))
                        .position(
                            x: geo.size.width / 2,
                            y: geo.size.height * 0.26 + CGFloat(index) * slabH * 1.35
                        )
                }
            }
        }
    }
}

private struct NetworkArt: View {
    let color: Color
    let seed: Int

    var body: some View {
        GeometryReader { geo in
            var generator = SeededGenerator(seed: seed)
            let width: CGFloat = geo.size.width
            let height: CGFloat = geo.size.height
            let base: CGFloat = min(width, height)
            let nodes: [CGPoint] = (0..<7).map { index -> CGPoint in
                let jitter: Double = Double.random(in: -0.2...0.2, using: &generator)
                let angle: Double = Double(index) / 7.0 * 2.0 * Double.pi + jitter
                let spread: Double = Double.random(in: 0.24...0.36, using: &generator)
                let radius: CGFloat = base * CGFloat(spread)
                return CGPoint(
                    x: width / 2 + CGFloat(cos(angle)) * radius,
                    y: height / 2 + CGFloat(sin(angle)) * radius
                )
            }
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                Path { path in
                    for node in nodes {
                        path.move(to: center)
                        path.addLine(to: node)
                    }
                    for index in 0..<nodes.count {
                        path.move(to: nodes[index])
                        path.addLine(to: nodes[(index + 2) % nodes.count])
                    }
                }
                .stroke(Comic.ink.opacity(0.75), lineWidth: 2)

                ForEach(0..<nodes.count, id: \.self) { index in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Comic.ink, lineWidth: 2.5))
                        .position(nodes[index])
                }
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Comic.ink, lineWidth: 3))
                    .position(center)
            }
        }
    }
}

private struct CurveArt: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let origin = CGPoint(x: geo.size.width * 0.14, y: geo.size.height * 0.82)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: origin.x, y: geo.size.height * 0.15))
                    path.addLine(to: origin)
                    path.addLine(to: CGPoint(x: geo.size.width * 0.88, y: origin.y))
                }
                .stroke(Comic.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Decaying loss curve.
                Path { path in
                    let steps = 40
                    for step in 0...steps {
                        let t = Double(step) / Double(steps)
                        let x = origin.x + t * (geo.size.width * 0.72)
                        let y = geo.size.height * 0.2 + (1 - exp(-3.2 * t)) * (geo.size.height * 0.58)
                        let point = CGPoint(x: x, y: geo.size.height * 1.02 - y)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))

                Path { path in
                    let steps = 40
                    for step in 0...steps {
                        let t = Double(step) / Double(steps)
                        let x = origin.x + t * (geo.size.width * 0.72)
                        let y = geo.size.height * 0.2 + (1 - exp(-3.2 * t)) * (geo.size.height * 0.58)
                        let point = CGPoint(x: x, y: geo.size.height * 1.02 - y)
                        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Comic.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
}

private struct TokenArt: View {
    let color: Color
    let seed: Int

    private struct Box {
        var rect: CGRect
        var filled: Bool
    }

    var body: some View {
        GeometryReader { geo in
            let boxes = layout(in: geo.size)
            ZStack(alignment: .topLeading) {
                ForEach(0..<boxes.count, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(boxes[index].filled ? color : Color.white)
                        .frame(width: boxes[index].rect.width, height: boxes[index].rect.height)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Comic.ink, lineWidth: 2.5))
                        .position(x: boxes[index].rect.midX, y: boxes[index].rect.midY)
                }
            }
        }
    }

    /// Lay the token chips out in wrapping rows, like text.
    private func layout(in size: CGSize) -> [Box] {
        var generator = SeededGenerator(seed: seed)
        let widths: [Double] = (0..<9).map { _ in Double.random(in: 0.09...0.22, using: &generator) }
        let rowHeight: CGFloat = size.height * 0.13
        let leftEdge = size.width * 0.1
        let rightEdge = size.width * 0.9
        let gap = size.width * 0.025

        var boxes: [Box] = []
        var x = leftEdge
        var row = 0
        for (index, width) in widths.enumerated() {
            let boxWidth: CGFloat = size.width * CGFloat(width)
            if x + boxWidth > rightEdge {
                x = leftEdge
                row += 1
            }
            boxes.append(Box(
                rect: CGRect(
                    x: x,
                    y: size.height * 0.28 + CGFloat(row) * rowHeight,
                    width: boxWidth,
                    height: rowHeight * 0.72
                ),
                filled: index.isMultiple(of: 3)
            ))
            x += boxWidth + gap
        }
        return boxes
    }
}

private struct ClusterArt: View {
    let color: Color
    let seed: Int

    var body: some View {
        GeometryReader { geo in
            var generator = SeededGenerator(seed: seed)
            let centers = [
                CGPoint(x: geo.size.width * 0.3, y: geo.size.height * 0.35),
                CGPoint(x: geo.size.width * 0.68, y: geo.size.height * 0.42),
                CGPoint(x: geo.size.width * 0.45, y: geo.size.height * 0.72)
            ]
            let spread: CGFloat = min(geo.size.width, geo.size.height) * 0.13
            let dots: [(CGPoint, Int)] = centers.enumerated().flatMap { clusterIndex, center -> [(CGPoint, Int)] in
                (0..<6).map { _ -> (CGPoint, Int) in
                    let dx: CGFloat = CGFloat(Double.random(in: -1...1, using: &generator)) * spread
                    let dy: CGFloat = CGFloat(Double.random(in: -1...1, using: &generator)) * spread
                    return (CGPoint(x: center.x + dx, y: center.y + dy), clusterIndex)
                }
            }

            ZStack {
                ForEach(0..<centers.count, id: \.self) { index in
                    Circle()
                        .stroke(Comic.ink.opacity(0.5), style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
                        .frame(width: spread * 3, height: spread * 3)
                        .position(centers[index])
                }
                ForEach(0..<dots.count, id: \.self) { index in
                    Circle()
                        .fill(dots[index].1 == 1 ? color : Color.white)
                        .frame(width: 15, height: 15)
                        .overlay(Circle().stroke(Comic.ink, lineWidth: 2.5))
                        .position(dots[index].0)
                }
            }
        }
    }
}

// MARK: - Deterministic randomness

/// Same card, same picture, every time — but different pictures across cards.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        if state == 0 { state = 0x4d595df4d0f33173 }
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
