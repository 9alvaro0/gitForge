import SwiftUI

/// `.gf-status-tag` — A/M/D/?/etc. small badge.
struct StatusTag: View {
    enum Kind { case added, modified, deleted, untracked, renamed, copied, typeChanged, unmerged, ignored }

    let kind: Kind

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(letter)
            .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
            .frame(width: DesignTokens.IconSize.xl, height: DesignTokens.IconSize.xl)
            .foregroundStyle(color)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.xs).fill(color.opacity(DesignTokens.Opacity.muted)))
    }

    private var letter: String {
        switch kind {
        case .added:        return "A"
        case .modified:     return "M"
        case .deleted:      return "D"
        case .untracked:    return "?"
        case .renamed:      return "R"
        case .copied:       return "C"
        case .typeChanged:  return "T"
        case .unmerged:     return "U"
        case .ignored:      return "!"
        }
    }
    private var color: Color {
        switch kind {
        case .added:        return theme.palette.add
        case .modified:     return theme.palette.mod
        case .deleted:      return theme.palette.del
        case .untracked:    return theme.palette.fg3
        case .renamed:      return theme.palette.info
        case .copied:       return theme.palette.info
        case .typeChanged:  return theme.palette.mod
        case .unmerged:     return theme.palette.del
        case .ignored:      return theme.palette.fg4
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    HStack(spacing: DesignTokens.Spacing.md) {
        StatusTag(kind: .added)
        StatusTag(kind: .modified)
        StatusTag(kind: .deleted)
        StatusTag(kind: .untracked)
        StatusTag(kind: .renamed)
        StatusTag(kind: .copied)
        StatusTag(kind: .typeChanged)
        StatusTag(kind: .unmerged)
        StatusTag(kind: .ignored)
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
