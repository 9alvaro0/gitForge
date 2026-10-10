import SwiftUI

/// The two sides of a conflict. Ours is `info` and points left, theirs is
/// `warn` and points right: colour is never the only cue.
enum ConflictSide {
    case ours, theirs

    var label: String {
        switch self {
        case .ours: "◀ OURS"
        case .theirs: "THEIRS ▶"
        }
    }

    func color(_ colors: GFColors) -> Color {
        switch self {
        case .ours: colors.info
        case .theirs: colors.warn
        }
    }

    func soft(_ colors: GFColors) -> Color {
        switch self {
        case .ours: colors.infoSoft
        case .theirs: colors.warnSoft
        }
    }
}

/// One code line in a hunk side or in the result: number, optional mark,
/// code in mono with the side's tint behind it.
struct ConflictCodeLine: View {
    let number: Int?
    let text: String
    var tint: Color = .clear
    var mark: String = ""
    var markColor: Color = .clear
    var markWidth: CGFloat = 16

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(number.map(String.init) ?? "")
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textQuaternary)
                .frame(width: 36, alignment: .trailing)
                .padding(.trailing, Spacing.s8)
            Text(mark)
                .font(AppFont.font(.caption, weight: .bold))
                .foregroundStyle(markColor)
                .frame(width: markWidth, alignment: .leading)
            // Long lines wrap: the hunk sides are half the width, and a cut
            // line could hide exactly the part that differs.
            Text(text.isEmpty ? " " : text)
                .font(AppFont.font(.mono, monoFamily: theme.monoFont))
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, Spacing.s8)
        }
        .frame(minHeight: theme.density.metrics.diffLine)
        .background(tint)
    }
}

/// Small solid or tinted button for picking a side, with its arrow.
struct ConflictSideButton: View {
    let side: ConflictSide
    let title: String
    var isPicked: Bool = false
    let action: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s6) {
                if side == .ours { Text("◀").accessibilityHidden(true) }
                Text(title)
                if side == .theirs { Text("▶").accessibilityHidden(true) }
            }
            .textRole(.callout, weight: .semibold)
            .foregroundStyle(onFill)
            .padding(.horizontal, Spacing.s12)
            .frame(height: theme.density.metrics.buttonRegular)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(side.color(theme.colors)))
            .overlay(RoundedRectangle(cornerRadius: Radius.control).fill(.white.opacity(hovering ? 0.08 : 0)))
            .contentShape(.rect(cornerRadius: Radius.control))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    /// Dark text on the light dark-mode fills, white on the deep light-mode ones.
    private var onFill: Color {
        theme.variant.isDark ? Color(hex: 0x101014) : .white
    }
}
