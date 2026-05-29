import SwiftUI

/// The original, code-drawn built-in pets. Drawn with SwiftUI shapes (no
/// third-party art, no copyright concerns) and animated per mood.
enum PetKind: String, CaseIterable, Identifiable {
    case blob
    case ghost
    case bot

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blob: return "Blob"
        case .ghost: return "Ghost"
        case .bot: return "Bot"
        }
    }

    var tint: Color {
        switch self {
        case .blob: return Color(red: 0.55, green: 0.46, blue: 0.96)
        case .ghost: return Color(red: 0.38, green: 0.80, blue: 0.78)
        case .bot: return Color(red: 0.97, green: 0.62, blue: 0.30)
        }
    }
}
