import SwiftUI

/// v2 semantic type roles (redesign spec §4.2). SF Pro for text, the user's
/// code font for the two mono roles. Replaces `FontSize` in phase F9.
nonisolated enum TypeRole: CaseIterable, Sendable {
    case largeTitle
    case title
    case headline
    case body
    case callout
    case caption
    case mono
    case monoSmall

    var size: CGFloat {
        switch self {
        case .largeTitle: 28
        case .title: 20
        case .headline: 15
        case .body: 13
        case .callout: 12
        case .caption: 11
        case .mono: 12
        case .monoSmall: 11
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 26
        case .headline: 20
        case .body: 18
        case .callout: 16
        case .caption: 14
        case .mono: 19
        case .monoSmall: 14
        }
    }

    /// Default weight. Buttons use `callout` Semibold and column headers
    /// `caption` Semibold by passing `weight:` explicitly.
    var weight: Font.Weight {
        switch self {
        case .largeTitle: .bold
        case .title, .headline: .semibold
        case .caption: .medium
        case .body, .callout, .mono, .monoSmall: .regular
        }
    }

    var tracking: CGFloat {
        switch self {
        case .largeTitle: -0.6
        case .title: -0.3
        case .headline: -0.15
        case .body, .callout, .caption, .mono, .monoSmall: 0
        }
    }

    var isMono: Bool { self == .mono || self == .monoSmall }

    /// Extra leading that brings a font's natural line height up to
    /// `lineHeight`. SwiftUI's `lineSpacing` adds to the font's own line
    /// height (about 1.2× its size), not to the point size.
    func lineSpacing(over naturalLineHeight: CGFloat) -> CGFloat {
        max(0, lineHeight - naturalLineHeight)
    }

    /// Natural line height of the font this role renders with. Weight barely
    /// moves it, so the regular face stands in for every weight.
    @MainActor
    func naturalLineHeight(monoFamily: MonoFontFamily) -> CGFloat {
        let font: NSFont
        if isMono {
            font = monoFamily == .systemMono
                ? .monospacedSystemFont(ofSize: size, weight: .regular)
                : NSFont(name: monoFamily.rawValue, size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        } else {
            font = .systemFont(ofSize: size)
        }
        return NSLayoutManager().defaultLineHeight(for: font)
    }
}

extension AppFont {
    /// Font for a v2 type role.
    static func font(_ role: TypeRole, weight: Font.Weight? = nil, monoFamily: MonoFontFamily = .systemMono) -> Font {
        let resolvedWeight = weight ?? role.weight
        if role.isMono {
            return mono(role.size, weight: resolvedWeight, family: monoFamily)
        }
        return .system(size: role.size, weight: resolvedWeight)
    }
}

private struct TextRoleModifier: ViewModifier {
    let role: TypeRole
    let weight: Font.Weight?

    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .font(AppFont.font(role, weight: weight, monoFamily: theme.monoFont))
            .tracking(role.tracking)
            .lineSpacing(role.lineSpacing(over: role.naturalLineHeight(monoFamily: theme.monoFont)))
    }
}

extension View {
    /// Applies a v2 type role: font, tracking and line height.
    func textRole(_ role: TypeRole, weight: Font.Weight? = nil) -> some View {
        modifier(TextRoleModifier(role: role, weight: weight))
    }
}
