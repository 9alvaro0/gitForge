import SwiftUI

struct PullRequestFileRow: View {
    let file: PullRequestFileChange
    let isSelected: Bool
    /// Unresolved review threads on the file, outdated ones included.
    var openThreads: Int = 0
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    private var directory: String {
        let dir = (file.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
    private var fileName: String { (file.path as NSString).lastPathComponent }

    private var rowFill: Color {
        if isSelected { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                StatusTag(kind: StatusTag.Kind(pullRequestFile: file.status))
                // Folder dim, file name bright: the name is what the eye scans.
                Text("\(Text(directory).foregroundStyle(theme.colors.textQuaternary))\(Text(fileName).foregroundStyle(theme.colors.textPrimary))")
                    .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if openThreads > 0 {
                    ThreadCountBadge(count: openThreads)
                }
                if file.additions > 0 {
                    Text("+\(file.additions)").foregroundStyle(theme.colors.add)
                }
                if file.deletions > 0 {
                    Text("−\(file.deletions)").foregroundStyle(theme.colors.del)
                }
            }
            .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
            .padding(.horizontal, Spacing.s8)
            .frame(height: theme.density.metrics.rowFile)
            .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(rowFill))
            .contentShape(.rect(cornerRadius: Radius.controlSmall))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension PullRequestFileRow {
    private var accessibilityText: String {
        let changes = String(localized: "\(file.path), \(file.additions) additions, \(file.deletions) deletions")
        guard openThreads > 0 else { return changes }
        return openThreads == 1 ? String(localized: "\(changes), 1 open comment")
                                : String(localized: "\(changes), \(openThreads) open comments")
    }
}

/// The fixed first row of the file list when threads sit on files the PR
/// no longer lists.
struct PullRequestOtherCommentsRow: View {
    /// Their unresolved threads.
    let openThreads: Int
    let isSelected: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @State private var hovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(theme.colors.textSecondary)
                Text("Other comments")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if openThreads > 0 {
                    ThreadCountBadge(count: openThreads)
                }
            }
            .padding(.horizontal, Spacing.s8)
            .frame(height: theme.density.metrics.rowFile)
            .background(RoundedRectangle(cornerRadius: Radius.controlSmall)
                .fill(isSelected ? theme.colors.accentSoft : hovering ? theme.colors.fillHover : .clear))
            .contentShape(.rect(cornerRadius: Radius.controlSmall))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(openThreads == 1 ? String(localized: "Other comments, 1 open")
                                             : String(localized: "Other comments, \(openThreads) open"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A speech bubble and how many threads are open.
struct ThreadCountBadge: View {
    let count: Int

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s2) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 9))
            Text("\(count)")
                .font(AppFont.font(.monoSmall, monoFamily: theme.monoFont))
        }
        .foregroundStyle(theme.colors.accent)
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let samples = PullRequestFileChange.previewSamples
    VStack(spacing: 0) {
        PullRequestOtherCommentsRow(openThreads: 2, isSelected: false, onSelect: {})
        if let first = samples.first {
            PullRequestFileRow(file: first, isSelected: true, openThreads: 3, onSelect: {})
        }
        ForEach(samples.dropFirst()) { file in
            PullRequestFileRow(file: file, isSelected: false, onSelect: {})
        }
    }
    .padding()
    .frame(width: 480)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
