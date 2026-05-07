import SwiftUI

/// `.gf-branch-chip` — branch / tag chip rendered next to commit messages.
struct BranchChip: View {
    let name: String
    var current: Bool = false
    var remote: Bool = false
    var tag: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: 4) {
            GFIcon(kind: tag ? .diamond : .branch, size: 10, stroke: foreground)
            Text(name)
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .padding(.vertical, 1)
        .foregroundStyle(foreground)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(border, lineWidth: 1)
        )
    }

    private var foreground: Color {
        if current { return theme.palette.accent }
        if tag     { return theme.palette.mod }
        if remote  { return theme.palette.info }
        return theme.palette.fg2
    }
    private var background: Color {
        if current { return theme.palette.accent.opacity(0.15) }
        if tag     { return theme.palette.mod.opacity(0.12) }
        if remote  { return theme.palette.bg3 }
        return theme.palette.bg3
    }
    private var border: Color {
        if current { return theme.palette.accent.opacity(0.30) }
        if tag     { return theme.palette.mod.opacity(0.30) }
        if remote  { return theme.palette.info.opacity(0.30) }
        return theme.palette.lineStrong
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: 8) {
        BranchChip(name: "feat/commit-graph", current: true)
        BranchChip(name: "main")
        BranchChip(name: "origin/main", remote: true)
        BranchChip(name: "v2.3.1", tag: true)
    }
    .padding(20)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
