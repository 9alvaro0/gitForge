import SwiftUI

enum Density: String, CaseIterable, Identifiable, Sendable {
    case compact
    case regular

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// Reads a stored value. `comfy` (dropped in the v2 redesign) and anything
    /// unknown fall back to `.regular`.
    static func resolve(_ raw: String?) -> Density {
        raw.flatMap(Density.init(rawValue:)) ?? .regular
    }

    /// v2 row heights, widths and graph geometry.
    var metrics: DensityMetrics {
        switch self {
        case .compact: .compact
        case .regular: .regular
        }
    }

    /// v1 row height for the commit graph table. Removed in phase F9.
    var rowHeight: CGFloat {
        switch self {
        case .compact: 26
        case .regular: 30
        }
    }

    /// v1 monospace size. Removed in phase F9.
    var monoFontSize: CGFloat {
        switch self {
        case .compact: 11.5
        case .regular: 12.5
        }
    }
}
