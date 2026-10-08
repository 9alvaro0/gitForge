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
        Self.installed.contains(self)
    }

    /// Resolved once per launch: `AppFont.mono` runs for every monospaced
    /// label on every render, and an `NSFont(name:)` lookup each time added
    /// up. A font installed while the app runs shows up after a relaunch.
    private static let installed: Set<MonoFontFamily> = Set(allCases.filter {
        $0 == .systemMono || NSFont(name: $0.rawValue, size: 12) != nil
    })

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

/// Type scale. Use these instead of raw numbers when calling
/// `AppFont.sans/.mono`. Mono blocks that should follow the user's density
/// preference use `theme.density.monoFontSize` instead.
///
/// The steps mirror the sizes the UI actually used when it was tokenised
/// (A07), half-points included, so adopting the scale changed nothing
/// visually. A redesign that wants fewer steps edits the values here.
enum FontSize {
    static let xxs: CGFloat = 10
    static let xs: CGFloat = 10.5
    static let sm: CGFloat = 11
    static let smPlus: CGFloat = 11.5
    static let md: CGFloat = 12
    static let mdPlus: CGFloat = 12.5
    static let lg: CGFloat = 13
    static let xl: CGFloat = 14
    static let xxl: CGFloat = 15
    static let xxxl: CGFloat = 16
    static let title: CGFloat = 18
    static let largeTitle: CGFloat = 20
    static let display: CGFloat = 56
}

/// Centralized font factory. The original design specifies Inter Tight for
/// sans and a configurable mono. **No font is bundled with the app**: Inter
/// Tight is only used when the user happens to have it installed, so in
/// practice the UI renders in SF Pro (the system fallback). Bundling it or
/// adopting SF Pro officially is a redesign decision (see audit A07).
enum AppFont {
    /// Resolved once per launch instead of per call (see `MonoFontFamily.installed`).
    private static let hasInterTight =
        NSFont(name: "InterTight-Regular", size: 12) != nil || NSFont(name: "Inter Tight", size: 12) != nil

    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if hasInterTight {
            return .custom("Inter Tight", size: size).weight(weight)
        }
        // Fallback — SF Pro / system sans.
        return .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular, family: MonoFontFamily = .systemMono) -> Font {
        if family != .systemMono, family.isAvailable {
            return .custom(family.rawValue, size: size).weight(weight)
        }
        // Fallback — SF Mono via .monospaced design.
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
