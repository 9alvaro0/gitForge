import Foundation

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
