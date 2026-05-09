import SwiftUI

/// "Both" lives as a footer button rather than a third visual pane so the
/// card stays focused on ours/theirs and the rare combined choice doesn't
/// dominate the layout.
struct ConflictHunkCard: View {
    let hunk: ConflictHunk
    let index: Int
    let pick: ConflictHunk.Pick?
    let currentBranchName: String?
    let onPick: (ConflictHunk.Pick) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.none) {
            header
            ConflictSection(
                title: "ours",
                subtitle: currentBranchName ?? "HEAD",
                lines: hunk.ours,
                tagColor: theme.palette.add,
                rowBackground: theme.palette.addSoft,
                isPicked: pick == .ours,
                actionLabel: "Pick ours",
                onPick: { onPick(.ours) }
            )
            divider
            ConflictSection(
                title: "theirs",
                subtitle: "incoming",
                lines: hunk.theirs,
                tagColor: theme.palette.info,
                rowBackground: theme.palette.info.opacity(DesignTokens.Opacity.subtle),
                isPicked: pick == .theirs,
                actionLabel: "Pick theirs",
                onPick: { onPick(.theirs) }
            )
            divider
            pickBothFooter
            // Result preview — what gets written when "Mark resolved" runs.
            // Lives here so the user can verify combined picks (especially
            // "both") before committing.
            divider
            ConflictSection(
                title: "result",
                subtitle: resultSubtitle,
                lines: pick.map { hunk.lines(for: $0) } ?? [],
                tagColor: theme.palette.accent,
                rowBackground: theme.palette.accent.opacity(DesignTokens.Opacity.subtle),
                isPicked: false,
                actionLabel: nil,
                onPick: nil,
                emptyMessage: "Pick a side above to preview the merged result."
            )
        }
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Text("Conflict #\(index + 1)")
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
            Text("· \(hunk.ours.count) vs \(hunk.theirs.count) lines")
                .font(AppFont.mono(11, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
            Spacer()
            if let pick {
                Pill(text: "picked → \(pick.rawValue)", kind: .neutral)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xl).padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }

    private var divider: some View {
        Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular)
    }

    private var pickBothFooter: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Button {
                onPick(.both)
            } label: {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    GFIcon(kind: .plus, size: 11, stroke: pick == .both ? theme.palette.accent : theme.palette.fg2)
                    Text("Pick both (ours + theirs)")
                        .font(AppFont.sans(11.5, weight: pick == .both ? .medium : .regular))
                        .foregroundStyle(pick == .both ? theme.palette.accent : theme.palette.fg2)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.sm)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .fill(pick == .both ? theme.palette.accent.opacity(DesignTokens.Opacity.subtle) : .clear))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
                    .stroke(pick == .both ? theme.palette.accent : theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
                .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.xl)
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg2)
    }

    private var resultSubtitle: String {
        guard let pick else { return "no pick yet" }
        switch pick {
        case .ours:   return "from ours · \(hunk.ours.count) lines"
        case .theirs: return "from theirs · \(hunk.theirs.count) lines"
        case .both:   return "ours + theirs · \(hunk.ours.count + hunk.theirs.count) lines"
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ConflictHunkCard(
        hunk: ConflictHunk.previewSamples[0],
        index: 0,
        pick: .ours,
        currentBranchName: "main",
        onPick: { _ in }
    )
    .padding()
    .frame(width: 720)
    .background(theme.palette.bg2)
    .appTheme(theme)
}
