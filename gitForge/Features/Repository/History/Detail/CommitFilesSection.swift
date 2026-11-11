import SwiftUI
import AppKit

/// The commit's changed files under its header: a count that stays put
/// and the list, which scrolls on its own (audit M5). Reads and writes
/// History's selection; `CommitFileList` is the list itself, for views that
/// keep their own (Recover lost commits).
struct CommitFilesSection: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        CommitFileList(
            files: viewModel.history.detailCache[commit.sha]?.files,
            repositoryURL: viewModel.repository.url,
            selection: viewModel.history.selectedCommitFile,
            revision: commit.sha
        ) { viewModel.history.selectedCommitFile = $0 }
    }
}

/// A commit's changed files: the count, then the rows (with arrow-key
/// navigation), or a skeleton while `files` is `nil`.
struct CommitFileList: View {
    /// `nil` while the commit's detail is loading.
    let files: [CommitFileChange]?
    let repositoryURL: URL
    let selection: String?
    /// The commit the files belong to: "Show file history" selects it.
    var revision: String? = nil
    let onSelect: (String) -> Void

    @Environment(\.appTheme) private var theme
    @FocusState private var listFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            header
            InspectorScrollArea {
                if let files {
                    ScrollViewReader { proxy in
                        LazyVStack(spacing: 1) {
                            ForEach(files) { f in
                                FileMiniRow(
                                    file: f,
                                    absoluteURL: repositoryURL.appendingPathComponent(f.path),
                                    isActive: selection == f.path,
                                    revision: revision
                                ) {
                                    onSelect(f.path)
                                    listFocused = true
                                }
                                .id(f.path)
                            }
                        }
                        .listKeyboardNavigation(
                            ids: files.map(\.path),
                            selection: selection,
                            isFocused: $listFocused,
                            scrollProxy: proxy
                        ) { onSelect($0) }
                    }
                } else {
                    placeholder
                }
            }
            .frame(minHeight: HistoryInspectorMetrics.minFileListHeight)
        }
    }

    private var fileCount: Int { files?.count ?? 0 }

    private var header: some View {
        HStack(spacing: Spacing.s4) {
            Text(fileCount == 1 ? String(localized: "1 file changed") : String(localized: "\(fileCount) files changed"))
                .textRole(.caption, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
        }
        .padding(.horizontal, Spacing.s16 + Spacing.s8)
    }

    // Bland filler — visible only while the commit detail is loading.
    private static let placeholderPaths = [
        String(localized: "Loading file path…"),
        String(localized: "Loading file path…"),
        String(localized: "Loading file path…"),
        String(localized: "Loading file path…"),
    ]

    private var placeholder: some View {
        LazyVStack(spacing: 1) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: Spacing.s8) {
                    StatusTag(kind: .modified)
                    Text(Self.placeholderPaths[index % Self.placeholderPaths.count])
                        .textRole(.mono)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.s8)
                .padding(.vertical, Spacing.s6)
            }
        }
        .skeleton(true)
    }
}

private struct FileMiniRow: View {
    let file: CommitFileChange
    let absoluteURL: URL
    let isActive: Bool
    let revision: String?
    let onSelect: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.fileInspector) private var fileInspector

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
            FileInspectorMenuItems(action: fileInspector, path: file.path, revision: revision,
                                   isDeleted: file.status == .deleted)
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
        case .added, .untracked: String(localized: "added")
        case .deleted:           String(localized: "deleted")
        case .renamed:           String(localized: "renamed")
        case .copied:            String(localized: "copied")
        case .unmerged:          String(localized: "conflicted")
        default:                 String(localized: "modified")
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
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
