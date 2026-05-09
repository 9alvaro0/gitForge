import SwiftUI
import AppKit

struct CommitFilesSection: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme

    private var detail: CommitDetail? { viewModel.detailCache[commit.sha] }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            header
            if let detail {
                LazyVStack(spacing: DesignTokens.Spacing.hairline) {
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
        HStack {
            Text("FILES CHANGED")
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            Text("\(detail?.files.count ?? 0)")
                .font(.system(size: FontSize.footnote))
                .foregroundStyle(theme.palette.fg3)
        }
    }

    private static let placeholderPaths = [
        "Sources/Features/Repository/RepositoryView.swift",
        "Sources/Core/Git/GitCLI.swift",
        "Sources/DesignSystem/Components/EmptyState.swift",
        "README.md",
    ]

    private var placeholder: some View {
        LazyVStack(spacing: DesignTokens.Spacing.hairline) {
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: DesignTokens.Spacing.md) {
                    StatusTag(kind: .modified)
                    Text(Self.placeholderPaths[index % Self.placeholderPaths.count])
                        .font(AppFont.mono(11.5, family: theme.monoFont))
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
            HStack(spacing: DesignTokens.Spacing.md) {
                StatusTag(kind: tagKind)
                Text(file.path)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm).fill(isActive ? theme.palette.bg3 : .clear))
            .contentShape(.rect(cornerRadius: DesignTokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .contextMenu {
            // The file may have been deleted after the commit; the OS handles
            // missing-file fallout (Open just fails silently).
            Button("Open in editor") {
                NSWorkspace.shared.open(absoluteURL)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([absoluteURL])
            }
            Divider()
            Button("Copy path") { copyToPasteboard(file.path) }
            Button("Copy filename") { copyToPasteboard((file.path as NSString).lastPathComponent) }
        }
    }

    private func copyToPasteboard(_ string: String) {
        NSPasteboard.general.declareTypes([.string], owner: nil)
        NSPasteboard.general.setString(string, forType: .string)
    }

    private var tagKind: StatusTag.Kind {
        switch file.status {
        case .added: return .added
        case .modified, .typeChanged: return .modified
        case .deleted: return .deleted
        case .renamed: return .renamed
        case .copied: return .copied
        case .unmerged: return .unmerged
        case .unknown: return .modified
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitFilesSection(commit: .preview, viewModel: .preview)
        .padding()
        .frame(width: 380)
        .background(theme.palette.bg1)
        .appTheme(theme)
}
