import SwiftUI

enum MonoFontFamily: String, CaseIterable, Identifiable, Sendable {
    case jetbrainsMono = "JetBrains Mono"
    case ibmPlexMono   = "IBM Plex Mono"
    case firaCode      = "Fira Code"
    case sfMono        = "SF Mono"
    /// Sentinel for "use the OS-default monospaced font" — `AppFont.mono`
    /// resolves this via `Font.system(.monospaced)` so it never requires
    /// a registered family and always renders. Acts as the universal
    /// fallback when the user's pick isn't installed.
    case systemMono    = "System Monospaced"

    var id: String { rawValue }
    var label: String { rawValue }

    /// `true` when the font is registered with the OS so callers can render
    /// it without falling back to the system monospaced font. The
    /// `.systemMono` sentinel is always available.
    var isAvailable: Bool {
        if self == .systemMono { return true }
        return NSFont(name: rawValue, size: 12) != nil
    }

    /// Returns `self` if the font is installed, otherwise falls back to the
    /// system monospaced sentinel so persisted values survive uninstalls.
    func resolved() -> MonoFontFamily {
        isAvailable ? self : .systemMono
    }

    /// Subset of cases that the user can actually pick — anything missing
    /// from the system is hidden so we never offer a non-functional choice.
    static var availableCases: [MonoFontFamily] {
        allCases.filter(\.isAvailable)
    }
}

/// Semantic font sizes. Use these instead of raw numbers when calling `AppFont.sans/.mono`.
/// Sizes here are absolute — for monospace blocks that should follow the
/// user's density preference, use `theme.density.monoFontSize` instead.
enum FontSize {
    static let caption: CGFloat = 10
    static let footnote: CGFloat = 11
    static let body: CGFloat = 13
    static let headline: CGFloat = 15
    static let title: CGFloat = 18
    static let display: CGFloat = 56
}

/// Centralized font factory. The design uses Inter Tight for sans + a configurable mono.
/// We prefer the bundled families; fall back to system stack if unavailable.
enum AppFont {
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NSFont(name: "InterTight-Regular", size: size) != nil
            || NSFont(name: "Inter Tight", size: size) != nil {
            return .custom("Inter Tight", size: size).weight(weight)
        }
        // Fallback — SF Pro / system sans.
        return .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular, family: MonoFontFamily = .systemMono) -> Font {
        if family != .systemMono, NSFont(name: family.rawValue, size: size) != nil {
            return .custom(family.rawValue, size: size).weight(weight)
        }
        // Fallback — SF Mono via .monospaced design.
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
