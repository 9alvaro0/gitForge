import Foundation

/// The user-selectable accents and the values derived from each one
/// (redesign spec §4.1.1).
nonisolated enum AccentSwatch: CaseIterable, Sendable {
    case violet
    case green
    case coral
    case blue

    /// The colour shown in pickers and persisted under `appTheme.accent`.
    var swatch: UInt32 {
        switch self {
        case .violet: 0x7C5CFF
        case .green: 0x56B497
        case .coral: 0xFF7E6B
        case .blue: 0x5DA4FF
        }
    }

    /// Fill under text and buttons. Violet is deepened so white text on it
    /// reaches 4.9:1.
    var fill: UInt32 { self == .violet ? 0x7350FA : swatch }

    /// Text and glyphs drawn on `fill`.
    var onFill: UInt32 { self == .violet ? 0xFFFFFF : 0x101014 }

    /// Accent used for text, icons and the HEAD lane.
    func foreground(for variant: ThemeVariant) -> UInt32 {
        switch variant {
        case .dark:
            switch self {
            case .violet: 0xA08CFF
            case .green: 0x5FCDA9
            case .coral: 0xFF907F
            case .blue: 0x79B6FF
            }
        case .light:
            switch self {
            case .violet: 0x5B3DF5
            case .green: 0x1F7F5F
            case .coral: 0xC0452F
            case .blue: 0x1F66CC
            }
        case .highContrastDark:
            self == .violet
                ? 0xBBAAFF
                : ColorMath.raise(foreground(for: .dark), toContrast: 7, on: variant.contentBackground, toward: 0xFFFFFF)
        case .highContrastLight:
            self == .violet
                ? 0x4321D9
                : ColorMath.raise(foreground(for: .light), toContrast: 7, on: variant.contentBackground, toward: 0x000000)
        }
    }

    /// The swatch a stored accent maps to: itself when it is one, otherwise
    /// the closest hue. Older builds could persist any colour.
    static func nearest(toHex hex: UInt32) -> AccentSwatch {
        if let exact = allCases.first(where: { $0.swatch == hex }) { return exact }
        return allCases.min {
            ColorMath.hueDistance($0.swatch, hex) < ColorMath.hueDistance($1.swatch, hex)
        } ?? .violet
    }
}
