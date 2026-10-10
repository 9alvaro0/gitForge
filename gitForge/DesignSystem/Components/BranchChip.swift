import SwiftUI

/// Branch / tag chip rendered next to commit messages (redesign spec §5).
struct BranchChip: View {
    let name: String
    var current: Bool = false
    var remote: Bool = false
    var tag: Bool = false
    /// When `true` on a local-branch chip, the chip has a remote tracking
    /// counterpart pointing at the **same sha** (the typical "in sync" case).
    /// Renders the cloud icon trailing the name so a single chip says
    /// "this branch exists locally AND on the remote, both at this commit",
    /// instead of duplicating the chip side-by-side. Mirrors GitKraken.
    var hasRemoteCounterpart: Bool = false

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s4) {
            GFIcon(kind: iconKind, size: 11, stroke: foreground)
            Text(name)
                .textRole(tag ? .monoSmall : .caption, weight: .semibold)
                .lineLimit(1)
                .truncationMode(.tail)
            if hasRemoteCounterpart {
                Rectangle()
                    .fill(foreground.opacity(0.35))
                    .frame(width: 1, height: 10)
                GFIcon(kind: .cloud, size: 11, stroke: foreground)
            }
        }
        .padding(.horizontal, Spacing.s6)
        .frame(height: theme.density.metrics.graph.chipHeight)
        .foregroundStyle(foreground)
        .background(shape.fill(background))
        .overlay(shape.strokeBorder(border, lineWidth: 1))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.chip) }

    /// Local → monitor, remote → cloud, tag → tag. Origin reads at a glance
    /// without the `origin/` prefix. HEAD keeps the local glyph.
    private var iconKind: GFIconKind {
        if tag    { return .tag }
        if remote { return .cloud }
        return .desktop
    }

    // Redesign spec §5 (RefChip). The per-lane tint of local chips arrives
    // with the v2 lane colours in F3.
    private var foreground: Color {
        if current { return theme.colors.accentOnFill }
        if remote  { return theme.colors.textSecondary }
        return theme.colors.textPrimary
    }
    private var background: Color {
        if current { return theme.colors.accentFill }
        if remote  { return .clear }
        return theme.colors.fillControl
    }
    private var border: Color {
        current ? .clear : theme.colors.strokeControl
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        BranchChip(name: "feat/commit-graph", current: true)
        BranchChip(name: "main")
        BranchChip(name: "origin/main", remote: true)
        BranchChip(name: "v2.3.1", tag: true)
    }
    .padding(DesignTokens.Spacing.huge)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
