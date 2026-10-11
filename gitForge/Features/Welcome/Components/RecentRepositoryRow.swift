import SwiftUI
import AppKit

/// One recent repository on Welcome (artboard `Welcome`): initials tile,
/// name and path, branch, state and when it was last opened.
struct RecentRepositoryRow: View {
    let repo: Repository
    let state: RecentState?
    var onSelect: () -> Void
    var onRemove: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s12) {
                Text(initials)
                    .textRole(.body, weight: .bold)
                    .foregroundStyle(theme.colors.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: Radius.control).fill(theme.colors.accentSoft))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.name)
                        .textRole(.body, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(repo.path)
                        .textRole(.monoSmall)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(branch)
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 180, alignment: .leading)
                Text(statusText)
                    .textRole(.caption, weight: statusIsNotable ? .semibold : .regular)
                    .foregroundStyle(statusColor)
                    .frame(width: 96, alignment: .leading)
                Text(DateDisplayMode.relative.format(repo.lastOpenedAt))
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, Spacing.s12)
            .frame(height: 60)
            .background(RoundedRectangle(cornerRadius: Radius.card).fill(hovering ? theme.colors.fillHover : .clear))
            .contentShape(.rect(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(repo.name), \(branch.isEmpty ? "" : "\(branch), ")\(statusText)")
        .accessibilityHint(repo.path)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([repo.url])
            }
            Divider()
            Button("Remove from Recents", role: .destructive, action: onRemove)
        }
    }

    private var initials: String {
        String(repo.name.prefix(2)).lowercased()
    }

    private var branch: String {
        if case .ready(let summary) = state { return summary.branch ?? "detached" }
        return ""
    }

    private var statusText: String {
        switch state {
        case .ready(let summary): summary.label
        case .missing: "Missing"
        case .loading, nil: ""
        }
    }

    private var statusIsNotable: Bool {
        if case .ready(let summary) = state { return summary.label != "Clean" }
        return false
    }

    private var statusColor: Color {
        switch state {
        case .ready(let summary) where summary.behind > 0 && summary.changed == 0: theme.colors.warn
        case .ready(let summary) where summary.label != "Clean": theme.colors.textPrimary
        default: theme.colors.textTertiary
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    VStack(spacing: 2) {
        ForEach(Repository.previewSamples) { repo in
            RecentRepositoryRow(repo: repo, state: .ready(RecentRepoSummary(branch: "main", changed: 2, ahead: 0, behind: 0)),
                                onSelect: {}, onRemove: {})
        }
    }
    .frame(width: 720)
    .padding(Spacing.s24)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
