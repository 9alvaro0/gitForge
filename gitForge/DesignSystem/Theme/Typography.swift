import SwiftUI

enum MonoFontFamily: String, CaseIterable, Identifiable, Sendable {
    case jetbrainsMono = "JetBrains Mono"
    case ibmPlexMono   = "IBM Plex Mono"
    case firaCode      = "Fira Code"
    case sfMono        = "SF Mono"

    var id: String { rawValue }
    var label: String { rawValue }
}

/// Semantic font sizes. Use these instead of raw numbers when calling `AppFont.sans/.mono`.
/// Sizes here are absolute — `Density.fontSize` covers the "follows user density" case.
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

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular, family: MonoFontFamily = .jetbrainsMono) -> Font {
        if NSFont(name: family.rawValue, size: size) != nil {
            return .custom(family.rawValue, size: size).weight(weight)
        }
        // Fallback — SF Mono via .monospaced design.
        return .system(size: size, weight: weight, design: .monospaced)
    }
}
