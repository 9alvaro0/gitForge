import SwiftUI
import AppKit

struct CommitFilesSection: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme

    private var detail: CommitDetail? { viewModel.detailCache[commit.sha] }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            header
            if let detail {
                LazyVStack(spacing: 1) {
                    ForEach(detail.files) { f in
                        FileMiniRow(
                            file: f,
                            absoluteURL: viewModel.repository.url.appendingPathComponent(f.path),
                            isActive: viewModel.selectedCommitFile == f.path
                        ) {
                            viewModel.selectedCommitFile = f.path
                        }
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.s4) {
            Text(detail?.files.count == 1 ? "1 file changed" : "\(detail?.files.count ?? 0) files changed")
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, Spacing.s8)
    }

    // Bland filler — visible only while the commit detail is loading.
    private static let placeholderPaths = [
        "Loading file path…",
        "Loading file path…",
        "Loading file path…",
        "Loading file path…",
    ]

    private var placeholder: some View {
        LazyVStack(spacing: DesignTokens.Spacing.hairline) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: DesignTokens.Spacing.md) {
                    StatusTag(kind: .modified)
                    Text(Self.placeholderPaths[index % Self.placeholderPaths.count])
                        .font(AppFont.mono(FontSize.smPlus, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg2)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
        }
        .skeleton(true)
    }
}

private struct FileMiniRow: View {
    let file: CommitFileChange
    let absoluteURL: URL
    let isActive: Bool
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: Spacing.s8) {
                StatusTag(kind: tagKind)
                // Folder dim, file name bright: the name is what the eye scans.
                Text("\(Text(directory).foregroundStyle(theme.colors.textQuaternary))\(Text(fileName).foregroundStyle(theme.colors.textPrimary))")
                    .textRole(.monoSmall)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.s8)
            .frame(height: theme.density.metrics.rowFile)
            .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(rowFill))
            .contentShape(.rect(cornerRadius: Radius.controlSmall))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(file.path), \(statusName)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contextMenu {
            // The file may have been deleted after the commit; the OS handles
            // missing-file fallout (Open just fails silently).
            Button("Open in editor") {
                ExternalURL.openFile(absoluteURL)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
            }
            Divider()
            Button("Copy path") { copyToPasteboard(file.path) }
            Button("Copy filename") { copyToPasteboard((file.path as NSString).lastPathComponent) }
        }
    }

    @State private var hovering = false

    private var directory: String {
        let dir = (file.path as NSString).deletingLastPathComponent
        return dir.isEmpty ? "" : dir + "/"
    }
    private var fileName: String { (file.path as NSString).lastPathComponent }

    private var statusName: String {
        switch tagKind {
        case .added, .untracked: "added"
        case .deleted:           "deleted"
        case .renamed:           "renamed"
        case .copied:            "copied"
        case .unmerged:          "conflicted"
        default:                 "modified"
        }
    }

    private var rowFill: Color {
        if isActive { return theme.colors.accentSoft }
        return hovering ? theme.colors.fillHover : .clear
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    private var tagKind: StatusTag.Kind { StatusTag.Kind(commitFile: file.status) }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitFilesSection(commit: .preview, viewModel: .preview)
        .padding()
        .frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
