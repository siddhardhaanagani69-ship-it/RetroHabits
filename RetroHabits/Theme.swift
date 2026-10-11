import SwiftUI

/// App palette: iOS system colors, so screens look like the rest of the platform.
enum Palette {
    static let paper    = Color(.systemGroupedBackground)
    static let panel    = Color(.secondarySystemGroupedBackground)
    static let ink      = Color.primary
    static let hairline = Color(.separator)
    static let fill     = Color(.tertiarySystemFill)
    static let red      = Color(.systemRed)
    static let yellow   = Color(.systemYellow)
    static let blue     = Color(.systemBlue)
    static let orange   = Color(.systemOrange)
}

extension Font {
    /// Titles, labels and numbers (SF Pro, bold).
    static func heading(_ size: CGFloat) -> Font { .system(size: size * 0.82, weight: .bold) }
    /// Body text, medium weight.
    static func bodyMedium(_ size: CGFloat) -> Font { .system(size: size, weight: .medium) }
    /// Body text, regular weight.
    static func bodyRegular(_ size: CGFloat) -> Font { .system(size: size) }
}

extension AgendaSource {
    var displayName: String {
        switch self {
        case .canvas: return "Canvas"
        case .apple: return "Calendar"
        }
    }

    var tint: Color {
        switch self {
        case .canvas: return Palette.red
        case .apple: return Palette.blue
        }
    }
}
