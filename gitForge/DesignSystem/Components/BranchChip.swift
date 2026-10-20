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
    /// Caps the name so long branches truncate; `nil` leaves it unbounded.
    var maxNameWidth: CGFloat? = nil
    /// Graph lane colour of the commit the chip sits on. Tints the fill,
    /// border and glyph so the chip reads as part of its branch line. The
    /// name keeps the regular text colour: lane hues like amber are too
    /// light for text on a light background. Ignored on tags and on the
    /// current branch (which already takes the accent, HEAD's lane colour).
    var laneColor: Color? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s4) {
            glyph(symbol)
            Text(name)
                .textRole(tag ? .monoSmall : .caption, weight: .semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: maxNameWidth, alignment: .leading)
            if hasRemoteCounterpart {
                Rectangle()
                    .fill(glyphColor.opacity(0.35))
                    .frame(width: 1, height: 10)
                glyph("cloud")
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
    private var symbol: String {
        if tag    { return "tag" }
        if remote { return "cloud" }
        return "desktopcomputer"
    }

    private func glyph(_ name: String) -> some View {
        SymbolGlyph(name, size: 11)
            .foregroundStyle(glyphColor)
    }

    /// The lane tint when it applies (branch chips other than HEAD).
    private var tint: Color? {
        guard !current, !tag else { return nil }
        return laneColor
    }

    private var glyphColor: Color {
        tint ?? foreground
    }

    // Redesign spec §5 (RefChip).
    private var foreground: Color {
        if current { return theme.colors.accentOnFill }
        if remote  { return theme.colors.textSecondary }
        return theme.colors.textPrimary
    }
    private var background: Color {
        if current { return theme.colors.accentFill }
        if remote  { return .clear }
        if let tint { return tint.opacity(theme.effectiveMode == .dark ? 0.22 : 0.14) }
        return theme.colors.fillControl
    }
    private var border: Color {
        if current { return .clear }
        if let tint { return tint.opacity(theme.increasedContrast ? 1 : 0.6) }
        return theme.colors.strokeControl
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(alignment: .leading, spacing: Spacing.s8) {
        BranchChip(name: "feat/commit-graph", current: true)
        BranchChip(name: "main")
        BranchChip(name: "main", hasRemoteCounterpart: true, laneColor: LaneColors.color(.lane(.lane0), dark: true, accent: .accentColor))
        BranchChip(name: "feat/diff", laneColor: LaneColors.color(.lane(.lane3), dark: true, accent: .accentColor))
        BranchChip(name: "origin/fix/crash", remote: true, laneColor: LaneColors.color(.lane(.lane2), dark: true, accent: .accentColor))
        BranchChip(name: "origin/main", remote: true)
        BranchChip(name: "v2.3.1", tag: true)
    }
    .padding(Spacing.s20)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
