import SwiftUI

/// App palette. Light mode matches iOS's grouped look; dark mode uses deeper
/// charcoal surfaces (asset catalog colors Paper, Panel and Hairline).
enum Palette {
    static let paper    = Color("Paper")
    static let panel    = Color("Panel")
    static let ink      = Color.primary
    static let hairline = Color("Hairline")
    static let fill     = Color(.tertiarySystemFill)
    static let red      = Color(.systemRed)
    static let yellow   = Color(.systemYellow)
    /// The app's accent: crimson (AccentColor in the asset catalog).
    static let accent   = Color.accentColor
    static let orange   = Color(.systemOrange)
    static let purple   = Color(.systemPurple)
    static let green    = Color(.systemGreen)
    static let rose     = Color(red: 1.0, green: 0.42, blue: 0.48)
    /// The crimson-to-rose used for progress and range bars.
    static let accentGradient = LinearGradient(colors: [accent, rose], startPoint: .leading, endPoint: .trailing)
}

extension Font {
    /// Titles, labels and numbers (SF Pro, bold).
    static func heading(_ size: CGFloat) -> Font { .system(textStyle(for: size * 0.82), weight: .bold) }
    /// Body text, medium weight.
    static func bodyMedium(_ size: CGFloat) -> Font { .system(textStyle(for: size), weight: .medium) }
    /// Body text, regular weight.
    static func bodyRegular(_ size: CGFloat) -> Font { .system(textStyle(for: size)) }

    /// The text style whose default size is nearest the design size. Text styles
    /// scale with the user's Dynamic Type setting; a fixed `size:` never does.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: .largeTitle      // 34
        case 25..<30: .title         // 28
        case 21..<25: .title2        // 22
        case 18.5..<21: .title3      // 20
        case 16.5..<18.5: .body      // 17
        case 15.5..<16.5: .callout   // 16
        case 14..<15.5: .subheadline // 15
        case 12.5..<14: .footnote    // 13
        case 11.5..<12.5: .caption   // 12
        default: .caption2           // 11
        }
    }
}

extension AgendaSource {
    var displayName: String {
        switch self {
        case .canvas: return "Canvas"
        case .apple: return "Calendar"
        case .email: return "Email"
        case .routine: return "Weekly"
        }
    }

    var tint: Color {
        switch self {
        case .canvas: return Palette.red
        case .apple: return Palette.accent
        case .email: return Palette.orange
        case .routine: return Palette.purple
        }
    }
}
