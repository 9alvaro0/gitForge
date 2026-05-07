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

    /// Generic content padding token.
    var pad: CGFloat {
        switch self {
        case .compact: 10
        case .regular: 12
        case .comfy:   16
        }
    }

    /// Sans-serif size token.
    var fontSize: CGFloat {
        switch self {
        case .compact: 12
        case .regular: 13
        case .comfy:   14
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
