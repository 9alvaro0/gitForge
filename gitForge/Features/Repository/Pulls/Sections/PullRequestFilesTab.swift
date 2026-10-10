import SwiftUI

struct PullRequestFilesTab: View {
    let files: [PullRequestFileChange]
    let loading: Bool

    @Environment(\.appTheme) private var theme
    @State private var selectedPath: String?
    @State private var diffViewMode: DiffPane.ViewMode = .unified

    var body: some View {
        if files.isEmpty {
            if loading {
                placeholderList
            } else {
                EmptyState(icon: .diff, title: "No files changed")
            }
        } else {
            // Files over the diff: next to the PR list the detail is too
            // narrow for two columns.
            VStack(spacing: 0) {
                fileList
                    .frame(height: fileListHeight)
                Rectangle().fill(theme.colors.separator).frame(height: 1)
                diffPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if selectedPath == nil { selectedPath = files.first?.path }
            }
            .onChange(of: files) { _, newFiles in
                if let current = selectedPath, !newFiles.contains(where: { $0.path == current }) {
                    selectedPath = newFiles.first?.path
                }
            }
        }
    }

    /// Up to about seven rows, then it scrolls.
    private var fileListHeight: CGFloat {
        CGFloat(min(files.count, 7)) * theme.density.metrics.rowFile + Spacing.s6 * 2
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(files) { file in
                    PullRequestFileRow(
                        file: file,
                        isSelected: file.path == selectedPath,
                        onSelect: { selectedPath = file.path }
                    )
                }
            }
            .padding(Spacing.s6)
        }
    }

    private static let placeholderSamples: [PullRequestFileChange] = [
        .init(path: "Sources/Features/PullRequest/PullRequestDetailView.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/Core/Models/PullRequest.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/Core/RemoteHosting/GitHubProvider.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/Core/RemoteHosting/GitLabProvider.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Sources/DesignSystem/Components/Skeleton.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "README.md", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
        .init(path: "Tests/PullRequestTests.swift", oldPath: nil, status: .modified, additions: 10, deletions: 4, patch: nil),
    ]

    private var placeholderList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Self.placeholderSamples) { file in
                    PullRequestFileRow(file: file, isSelected: false, onSelect: {})
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .skeleton(true)
    }

    private var diffPane: some View {
        let selected = files.first(where: { $0.path == selectedPath })
        let hunks: [DiffHunk] = {
            guard let patch = selected?.patch, !patch.isEmpty else { return [] }
            return DiffParser.parse(patch)
        }()
        return DiffPane(
            file: selected?.path,
            status: selected.map { StatusTag.Kind(pullRequestFile: $0.status) },
            hunks: hunks,
            viewMode: $diffViewMode
        )
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    PullRequestFilesTab(files: PullRequestFileChange.previewSamples, loading: false)
        .frame(width: 1200, height: 720)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    PullRequestFilesTab(files: [], loading: true)
        .frame(width: 1200, height: 720)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
