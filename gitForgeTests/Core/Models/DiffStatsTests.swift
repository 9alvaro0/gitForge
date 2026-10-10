import Testing
@testable import gitForge

@Suite("DiffStats")
struct DiffStatsTests {

    private static func hunk(_ id: Int, _ kinds: [DiffLine.Kind]) -> DiffHunk {
        let lines = kinds.enumerated().map { index, kind in
            DiffLine(id: index, kind: kind, content: "x", oldLineNumber: nil, newLineNumber: nil)
        }
        return DiffHunk(id: id, oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, header: "@@", lines: lines)
    }

    @Test("Counts added and removed lines across hunks, ignoring context and no-newline markers")
    func countsAcrossHunks() {
        let stats = DiffStats(hunks: [
            Self.hunk(0, [.context, .removed, .added, .added, .noNewline]),
            Self.hunk(1, [.removed, .removed, .context, .added]),
        ])
        #expect(stats.additions == 3)
        #expect(stats.deletions == 3)
        #expect(!stats.isEmpty)
    }

    @Test("No hunks, or only context, is empty")
    func empty() {
        #expect(DiffStats(hunks: []).isEmpty)
        #expect(DiffStats(hunks: [Self.hunk(0, [.context, .context])]).isEmpty)
    }
}
