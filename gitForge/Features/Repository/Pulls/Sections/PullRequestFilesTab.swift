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
                EmptyState(icon: .diff, title: "No files changed", subtitle: nil) { EmptyView() }
            }
        } else {
            HStack(spacing: DesignTokens.Spacing.none) {
                fileList
                    .frame(width: DesignTokens.Pulls.listWidth)
                    .frame(maxHeight: .infinity)
                    .background(theme.palette.bg1)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(theme.palette.line).frame(width: DesignTokens.Stroke.regular)
                    }
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

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: DesignTokens.Spacing.none) {
                ForEach(files) { file in
                    PullRequestFileRow(
                        file: file,
                        isSelected: file.path == selectedPath,
                        onSelect: { selectedPath = file.path }
                    )
                }
            }
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
            LazyVStack(spacing: DesignTokens.Spacing.none) {
                ForEach(Self.placeholderSamples) { file in
                    PullRequestFileRow(file: file, isSelected: false, onSelect: {})
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.bg1)
        .skeleton(true)
    }

    private var diffPane: some View {
        let selected = files.first(where: { $0.path == selectedPath })
        let hunks: [DiffHunk] = {
            guard let patch = selected?.patch, !patch.isEmpty else { return [] }
            return DiffParser.parse(patch)
        }()
        return DiffPane(file: selected?.path, hunks: hunks, viewMode: $diffViewMode)
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = AppTheme()
    PullRequestFilesTab(files: PullRequestFileChange.previewSamples, loading: false)
        .frame(width: 1200, height: 720)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

#Preview("Loading") {
    @Previewable @State var theme = AppTheme()
    PullRequestFilesTab(files: [], loading: true)
        .frame(width: 1200, height: 720)
        .background(theme.palette.bg2)
        .appTheme(theme)
}
