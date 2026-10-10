import Foundation

/// The four colour variants of the v2 palette (redesign spec §4.1).
nonisolated enum ThemeVariant: CaseIterable, Sendable {
    case dark
    case light
    case highContrastDark
    case highContrastLight

    init(isDark: Bool, highContrast: Bool) {
        switch (isDark, highContrast) {
        case (true, false): self = .dark
        case (false, false): self = .light
        case (true, true): self = .highContrastDark
        case (false, true): self = .highContrastLight
        }
    }

    var isDark: Bool { self == .dark || self == .highContrastDark }
    var isHighContrast: Bool { self == .highContrastDark || self == .highContrastLight }

    /// `bg.content`, the surface most text sits on. Contrast targets are
    /// measured against it.
    var contentBackground: UInt32 {
        switch self {
        case .dark: 0x18181C
        case .light: 0xFFFFFF
        case .highContrastDark: 0x0A0A0C
        case .highContrastLight: 0xFFFFFF
        }
    }
}
