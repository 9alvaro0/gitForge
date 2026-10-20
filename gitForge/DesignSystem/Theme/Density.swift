import SwiftUI

enum Density: String, CaseIterable, Identifiable, Sendable {
    case compact
    case regular

    var id: String { rawValue }
    var label: String {
        switch self {
        case .compact: String(localized: "Compact")
        case .regular: String(localized: "Regular")
        }
    }

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
}

