import SwiftUI

enum MonoFontFamily: String, CaseIterable, Identifiable, Sendable {
    case jetbrainsMono = "JetBrains Mono"
    case ibmPlexMono   = "IBM Plex Mono"
    case firaCode      = "Fira Code"
    case sfMono        = "SF Mono"
    /// Sentinel for "use the OS-default monospaced font" — `AppFont.codeFace`
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

    /// Resolved once per launch: `AppFont.codeFace` runs for every monospaced
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

/// Font factory for the v2 type roles (`AppFont.font(_:weight:monoFamily:)`
/// in `TypeRole.swift`). The UI renders in SF Pro; the code font is the
/// user's pick from `MonoFontFamily`.
enum AppFont {
    /// The code font at `size`: the user's family when installed, else the
    /// system monospaced face.
    static func codeFace(_ size: CGFloat, weight: Font.Weight = .regular, family: MonoFontFamily = .systemMono) -> Font {
        if family != .systemMono, family.isAvailable {
            return .custom(family.rawValue, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
