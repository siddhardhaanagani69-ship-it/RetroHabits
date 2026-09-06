import SwiftUI

// MARK: - Comic panel (white card, ink border, hard offset shadow)

struct ComicPanel<Content: View>: View {
    var tilt: Double
    var fill: Color
    private let content: Content

    init(tilt: Double = 0, fill: Color = Comic.panel, @ViewBuilder content: () -> Content) {
        self.tilt = tilt
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Comic.ink)
                        .offset(x: 4, y: 4)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Comic.ink, lineWidth: 2.5)
                }
            )
            .rotationEffect(.degrees(tilt))
    }
}

// MARK: - Comic header banner

struct ComicHeader: View {
    var title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.bangers(38))
                .foregroundStyle(Comic.red)
                .shadow(color: Comic.ink, radius: 0, x: 2, y: 2)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.comic(14))
                    .foregroundStyle(Comic.ink.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Button style

struct ComicButtonStyle: ButtonStyle {
    var fill: Color = Comic.yellow
    var textColor: Color = Comic.ink

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.bangers(18))
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Comic.ink)
                        .offset(x: 3, y: 3)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Comic.ink, lineWidth: 2.5)
                }
            )
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Source tag

struct SourceTag: View {
    var source: AgendaSource

    var body: some View {
        Text(source.displayName)
            .font(.bangers(13))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(source.tint)
            )
            .overlay(Capsule().stroke(Comic.ink, lineWidth: 2))
    }
}

// MARK: - Comic progress bar

struct ComicProgressBar: View {
    /// 0...1
    var progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white)
                Capsule()
                    .fill(Comic.red)
                    .frame(width: max(0, geo.size.width * progress))
            }
            .overlay(Capsule().stroke(Comic.ink, lineWidth: 2.5))
        }
        .frame(height: 18)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: progress)
    }
}

// MARK: - Shapes for hero effects

struct StarburstShape: Shape {
    var points: Int = 14
    var innerRatio: CGFloat = 0.6

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * innerRatio
        let total = points * 2
        for i in 0..<total {
            let angle = (Double(i) / Double(total)) * 2 * .pi - .pi / 2
            let radius = i.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct WebShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4
            path.move(to: center)
            path.addLine(to: CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            ))
        }
        let rings: [CGFloat] = [0.35, 0.65, 0.95]
        for ring in rings {
            let r = radius * ring
            path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let unit: [CGPoint] = [
            CGPoint(x: 0.55, y: 0.00),
            CGPoint(x: 0.10, y: 0.55),
            CGPoint(x: 0.40, y: 0.55),
            CGPoint(x: 0.25, y: 1.00),
            CGPoint(x: 0.90, y: 0.38),
            CGPoint(x: 0.58, y: 0.38),
            CGPoint(x: 0.85, y: 0.00)
        ]
        var path = Path()
        let scaled = unit.map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height) }
        path.move(to: scaled[0])
        for point in scaled.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }
}

struct FlameShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.9, y: rect.minY + h * 0.65),
            control: CGPoint(x: rect.minX + w * 1.05, y: rect.minY + h * 0.25)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY + h),
            control: CGPoint(x: rect.minX + w * 0.95, y: rect.minY + h * 1.0)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.1, y: rect.minY + h * 0.65),
            control: CGPoint(x: rect.minX + w * 0.05, y: rect.minY + h * 1.0)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.5, y: rect.minY),
            control: CGPoint(x: rect.minX - w * 0.05, y: rect.minY + h * 0.25)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Hero burst effects (comic homages — webs, thunder, flames)

enum HeroEffect: CaseIterable {
    case web, thunder, flame

    var word: String {
        switch self {
        case .web: return "THWIP!"
        case .thunder: return "KRA-KOOM!"
        case .flame: return "BLAZE!"
        }
    }

    var burstColor: Color {
        switch self {
        case .web: return Comic.blue
        case .thunder: return Comic.yellow
        case .flame: return Comic.orange
        }
    }
}

struct HeroBurstView: View {
    let effect: HeroEffect
    @State private var appeared = false

    var body: some View {
        ZStack {
            StarburstShape(points: 14)
                .fill(effect.burstColor)
            StarburstShape(points: 14)
                .stroke(Comic.ink, lineWidth: 3)

            switch effect {
            case .web:
                WebShape()
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 150, height: 150)
                WebShape()
                    .stroke(Comic.ink, lineWidth: 1)
                    .frame(width: 150, height: 150)
            case .thunder:
                BoltShape()
                    .fill(Color.white)
                    .frame(width: 80, height: 130)
                BoltShape()
                    .stroke(Comic.ink, lineWidth: 3)
                    .frame(width: 80, height: 130)
            case .flame:
                FlameShape()
                    .fill(
                        LinearGradient(
                            colors: [Comic.yellow, Comic.orange, Comic.red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 90, height: 130)
                FlameShape()
                    .stroke(Comic.ink, lineWidth: 3)
                    .frame(width: 90, height: 130)
            }

            Text(effect.word)
                .font(.bangers(42))
                .foregroundStyle(.white)
                .shadow(color: Comic.ink, radius: 0, x: 2.5, y: 2.5)
                .rotationEffect(.degrees(-8))
                .offset(y: 8)
        }
        .frame(width: 250, height: 250)
        .scaleEffect(appeared ? 1 : 0.1)
        .rotationEffect(.degrees(appeared ? 0 : -20))
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                appeared = true
            }
        }
        .allowsHitTesting(false)
    }
}
