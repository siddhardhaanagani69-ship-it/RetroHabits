import SwiftUI

/// Comic book palette — bold primaries on aged paper with heavy black ink.
enum Comic {
    static let paper  = Color(red: 1.00, green: 0.96, blue: 0.86)
    static let panel  = Color.white
    static let ink    = Color.black
    static let red    = Color(red: 0.89, green: 0.12, blue: 0.15)
    static let yellow = Color(red: 1.00, green: 0.80, blue: 0.00)
    static let blue   = Color(red: 0.00, green: 0.45, blue: 0.85)
    static let orange = Color(red: 1.00, green: 0.45, blue: 0.05)
}

extension Font {
    /// Display font — big comic action lettering.
    static func bangers(_ size: CGFloat) -> Font { .custom("Bangers-Regular", size: size) }
    /// Body font, bold weight.
    static func comic(_ size: CGFloat) -> Font { .custom("ComicNeue-Bold", size: size) }
    /// Body font, regular weight.
    static func comicLight(_ size: CGFloat) -> Font { .custom("ComicNeue-Regular", size: size) }
}

extension AgendaSource {
    var displayName: String {
        switch self {
        case .canvas: return "CANVAS"
        case .apple: return "CALENDAR"
        }
    }

    var tint: Color {
        switch self {
        case .canvas: return Comic.red
        case .apple: return Comic.blue
        }
    }
}
