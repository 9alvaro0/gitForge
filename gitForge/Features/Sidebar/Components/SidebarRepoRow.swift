import SwiftUI

/// `.gf-repo` row inside the sidebar repository list.
struct SidebarRepoRow: View {
    let repository: Repository
    let org: String
    let branch: String?
    let ahead: Int
    let behind: Int
    let dirty: Int
    var loaded: Bool = true
    let isCurrent: Bool
    let onSelect: () -> Void
    var onRemove: (() -> Void)? = nil
    var onRevealInFinder: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s12) {
                RepoMark(letter: String(org.prefix(1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(repository.name)
                        .textRole(.body, weight: .medium)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                    if let branch {
                        Text(branch)
                            .textRole(.monoSmall)
                            .foregroundStyle(theme.colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusPills(ahead: ahead, behind: behind, dirty: dirty, loaded: loaded)
            }
            .padding(.horizontal, Spacing.s8)
            .padding(.vertical, Spacing.s6)
            .frame(height: LayoutMetrics.sidebarRepoRow)
            .background(RoundedRectangle(cornerRadius: Radius.row).fill(rowBackground))
            .contentShape(.rect(cornerRadius: Radius.row))
            .padding(.horizontal, Spacing.s6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            if let onRevealInFinder {
                Button("Reveal in Finder", action: onRevealInFinder)
            }
            if let onRemove {
                Divider()
                // Not destructive: removing from the recents list neither
                // deletes the repo nor loses any data. Marking it destructive
                // wrongly tells VoiceOver "this is dangerous" and red-tints
                // the menu item on macOS.
                Button("Remove from Recents", action: onRemove)
            }
        }
    }

    /// Current: `accentSoft`, like a selected list row (spec §5); hover:
    /// `fillHover`, so hovering never looks stronger than the current repo.
    private var rowBackground: Color {
        if isCurrent { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let samples = Repository.previewSamples
    VStack(spacing: 1) {
        ForEach(samples) { repo in
            let isCurrent = repo.id == samples.first?.id
            let status: RepoStatusSnapshot = isCurrent ? .previewActive : .previewClean
            SidebarRepoRow(repository: repo,
                           org: "9alvaro0",
                           branch: status.branch,
                           ahead: status.ahead,
                           behind: status.behind,
                           dirty: status.dirty,
                           isCurrent: isCurrent,
                           onSelect: {})
        }
    }
    .frame(width: 256)
    .padding(.vertical, Spacing.s6)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
