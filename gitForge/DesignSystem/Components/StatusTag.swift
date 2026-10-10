import SwiftUI

/// `.gf-status-tag` — A/M/D/?/etc. small badge.
struct StatusTag: View {
    enum Kind { case added, modified, deleted, untracked, renamed, copied, typeChanged, unmerged, ignored }

    let kind: Kind

    @Environment(\.appTheme) private var theme

    var body: some View {
        Text(letter)
            .font(AppFont.font(.monoSmall, weight: .bold, monoFamily: theme.monoFont))
            .frame(width: 16, height: 16)
            .foregroundStyle(colors.fg)
            .background(RoundedRectangle(cornerRadius: Radius.badge).fill(colors.soft))
    }

    private var letter: String {
        switch kind {
        case .added:        return "A"
        case .modified:     return "M"
        case .deleted:      return "D"
        case .untracked:    return "N"
        case .renamed:      return "R"
        case .copied:       return "C"
        case .typeChanged:  return "T"
        case .unmerged:     return "U"
        case .ignored:      return "!"
        }
    }
    private var colors: (fg: Color, soft: Color) {
        let c = theme.colors
        switch kind {
        case .added, .untracked:    return (c.add, c.addSoft)
        case .modified, .typeChanged: return (c.mod, c.modSoft)
        case .deleted, .unmerged:   return (c.del, c.delSoft)
        case .renamed, .copied:     return (c.info, c.infoSoft)
        case .ignored:              return (c.textQuaternary, c.fillControl)
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
