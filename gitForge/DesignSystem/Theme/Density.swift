import SwiftUI

enum Density: String, CaseIterable, Identifiable, Sendable {
    case compact
    case regular
    case comfy

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Row height for commit graph + similar dense lists.
    var rowHeight: CGFloat {
        switch self {
        case .compact: 26
        case .regular: 30
        case .comfy:   36
        }
    }

    /// Monospace size token.
    var monoFontSize: CGFloat {
        switch self {
        case .compact: 11.5
        case .regular: 12.5
        case .comfy:   13
        }
    }
}
