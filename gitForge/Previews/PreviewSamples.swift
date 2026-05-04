import Foundation

extension Repository {
    static let preview = Repository(
        url: URL(fileURLWithPath: "/Users/preview/Code/gitForge"),
        lastOpenedAt: .now
    )

    static let previewSamples: [Repository] = [
        Repository(
            url: URL(fileURLWithPath: "/Users/preview/Code/gitForge"),
            lastOpenedAt: .now
        ),
        Repository(
            url: URL(fileURLWithPath: "/Users/preview/Code/sandbox-app"),
            lastOpenedAt: .now.addingTimeInterval(-3_600)
        ),
        Repository(
            url: URL(fileURLWithPath: "/Users/preview/Code/website"),
            lastOpenedAt: .now.addingTimeInterval(-86_400)
        ),
    ]
}

extension Commit {
    static let preview = Commit(
        sha: "a1b2c3d4e5f6789012345678901234567890abcd",
        parentShas: ["b2c3d4e5f6789012345678901234567890abcdab"],
        authorName: "Alvaro Guerra",
        authorEmail: "alvaro@warwarelabs.com",
        authorDate: .now.addingTimeInterval(-3_600),
        subject: "feat: render commit graph with lanes"
    )

    static let previewSamples: [Commit] = [
        Commit(
            sha: "a1b2c3d4e5f6789012345678901234567890abcd",
            parentShas: ["b2c3d4e5f6789012345678901234567890abcdab"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-1_800),
            subject: "feat: render commit graph with lanes"
        ),
        Commit(
            sha: "b2c3d4e5f6789012345678901234567890abcdab",
            parentShas: ["c3d4e5f6789012345678901234567890abcdabcd", "d4e5f6789012345678901234567890abcdabcdef"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-7_200),
            subject: "Merge branch \"feature/working-copy\" into main"
        ),
        Commit(
            sha: "c3d4e5f6789012345678901234567890abcdabcd",
            parentShas: ["d4e5f6789012345678901234567890abcdabcdef"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-86_400),
            subject: "fix: avoid pipe deadlock with concurrent draining"
        ),
        Commit(
            sha: "d4e5f6789012345678901234567890abcdabcdef",
            parentShas: ["e5f6789012345678901234567890abcdabcdef12"],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-259_200),
            subject: "chore: organize sources into App, Features, Core"
        ),
        Commit(
            sha: "e5f6789012345678901234567890abcdabcdef12",
            parentShas: [],
            authorName: "Alvaro Guerra",
            authorEmail: "alvaro@warwarelabs.com",
            authorDate: .now.addingTimeInterval(-604_800),
            subject: "chore: initial project scaffold"
        ),
    ]
}

extension GitRef {
    static let previewSamples: [GitRef] = [
        GitRef(name: "main", kind: .localBranch, targetSha: "a1b2c3d4e5f6789012345678901234567890abcd", isHead: true),
        GitRef(name: "feature/working-copy", kind: .localBranch, targetSha: "b2c3d4e5f6789012345678901234567890abcdab", isHead: false),
        GitRef(name: "fix/pipe-deadlock", kind: .localBranch, targetSha: "c3d4e5f6789012345678901234567890abcdabcd", isHead: false),
        GitRef(name: "origin/main", kind: .remoteBranch(remote: "origin"), targetSha: "a1b2c3d4e5f6789012345678901234567890abcd", isHead: false),
        GitRef(name: "origin/feature/working-copy", kind: .remoteBranch(remote: "origin"), targetSha: "b2c3d4e5f6789012345678901234567890abcdab", isHead: false),
        GitRef(name: "v0.1.0", kind: .tag, targetSha: "e5f6789012345678901234567890abcdabcdef12", isHead: false),
    ]
}

extension CommitFileChange {
    static let previewSamples: [CommitFileChange] = [
        CommitFileChange(path: "gitForge/Features/Repository/CommitLogView.swift", status: .added),
        CommitFileChange(path: "gitForge/Features/Repository/RepositoryView.swift", status: .modified),
        CommitFileChange(path: "gitForge/Features/ContentView.swift", status: .deleted),
        CommitFileChange(
            path: "gitForge/Models/Commit.swift",
            status: .renamed(from: "gitForge/Models/CommitModel.swift")
        ),
    ]
}

extension CommitDetail {
    static let preview = CommitDetail(
        commit: Commit.preview,
        fullMessage: """
        feat: render commit graph with lanes

        - SwiftUI Canvas-based graph rendering
        - Lane assignment that handles merges and forks
        - Color palette stable across refresh
        - Aligned with the commit list rows
        """,
        files: CommitFileChange.previewSamples
    )
}

extension DiffHunk {
    static let previewSamples: [DiffHunk] = [
        DiffHunk(
            id: 0,
            oldStart: 12,
            oldCount: 6,
            newStart: 12,
            newCount: 8,
            header: "func loadInitial() async {",
            lines: [
                DiffLine(id: 0, kind: .context, content: "func loadInitial() async {", oldLineNumber: 12, newLineNumber: 12),
                DiffLine(id: 1, kind: .context, content: "    guard commits.isEmpty else { return }", oldLineNumber: 13, newLineNumber: 13),
                DiffLine(id: 2, kind: .removed, content: "    isLoading = true", oldLineNumber: 14, newLineNumber: nil),
                DiffLine(id: 3, kind: .added, content: "    isLoadingInitial = true", oldLineNumber: nil, newLineNumber: 14),
                DiffLine(id: 4, kind: .added, content: "    defer { isLoadingInitial = false }", oldLineNumber: nil, newLineNumber: 15),
                DiffLine(id: 5, kind: .context, content: "    do {", oldLineNumber: 15, newLineNumber: 16),
                DiffLine(id: 6, kind: .added, content: "        let page = try await cli.log(limit: 200)", oldLineNumber: nil, newLineNumber: 17),
                DiffLine(id: 7, kind: .context, content: "        commits = page", oldLineNumber: 16, newLineNumber: 18),
                DiffLine(id: 8, kind: .context, content: "    }", oldLineNumber: 17, newLineNumber: 19),
            ]
        ),
        DiffHunk(
            id: 1,
            oldStart: 32,
            oldCount: 3,
            newStart: 34,
            newCount: 4,
            header: "private func recomputeGraph() {",
            lines: [
                DiffLine(id: 0, kind: .context, content: "private func recomputeGraph() {", oldLineNumber: 32, newLineNumber: 34),
                DiffLine(id: 1, kind: .removed, content: "    graphLayouts = engine.layouts(commits: commits)", oldLineNumber: 33, newLineNumber: nil),
                DiffLine(id: 2, kind: .added, content: "    let result = GraphLayoutEngine.layouts(for: commits)", oldLineNumber: nil, newLineNumber: 35),
                DiffLine(id: 3, kind: .added, content: "    graphLayouts = result.rows", oldLineNumber: nil, newLineNumber: 36),
                DiffLine(id: 4, kind: .context, content: "}", oldLineNumber: 34, newLineNumber: 37),
            ]
        ),
    ]
}

extension WorkingCopyStatus {
    static let preview = WorkingCopyStatus(files: [
        WorkingCopyFile(path: "gitForge/Features/Repository/CommitLogView.swift", stagedStatus: .modified, unstagedStatus: .unmodified, originalPath: nil),
        WorkingCopyFile(path: "gitForge/Models/Commit.swift", stagedStatus: .added, unstagedStatus: .unmodified, originalPath: nil),
        WorkingCopyFile(path: "gitForge/App/AppState.swift", stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil),
        WorkingCopyFile(path: "README.md", stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil),
        WorkingCopyFile(path: "gitForge/Features/NewView.swift", stagedStatus: .unmodified, unstagedStatus: .untracked, originalPath: nil),
    ])
}

@MainActor
extension AppState {
    static var preview: AppState {
        let state = AppState()
        state.gitStatus = .available
        state.repositories = Repository.previewSamples
        return state
    }

    static var previewWithActive: AppState {
        let state = preview
        let repo = Repository.previewSamples.first!
        state.activeRepository = repo
        state.activeViewModel = RepositoryViewModel.preview
        return state
    }

    static var previewMissingGit: AppState {
        let state = AppState()
        state.gitStatus = .notFound
        return state
    }
}
