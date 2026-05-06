import Foundation

/// Sample data for redesigned views (`ConflictView`, command palette, …).
/// Lives only in the development asset folder.

extension ConflictFile {
    static let previewSamples: [ConflictFile] = [
        ConflictFile(path: "src/components/CommitGraph.tsx", resolved: false, conflicts: 2),
        ConflictFile(path: "src/store/commitStore.ts",        resolved: true,  conflicts: 1),
        ConflictFile(path: "package.json",                    resolved: false, conflicts: 1),
    ]
}

extension ConflictHunk {
    static let previewSamples: [ConflictHunk] = [
        ConflictHunk(
            ours:   ["  const rowH = density === \"compact\" ? 22 : 28",
                     "  const offsetY = scrollTop % rowH"],
            base:   ["  const rowH = 24",
                     "  const offsetY = 0"],
            theirs: ["  const rowH = density === \"compact\" ? 20 : 26",
                     "  const offsetY = scrollTop - (scrollTop % rowH)"]
        ),
        ConflictHunk(
            ours:   ["  return commits.slice(start, end)"],
            base:   ["  return commits"],
            theirs: ["  return memoize(commits.slice(start, end))"]
        ),
    ]
}

extension Array where Element == GraphRowLayout {
    /// Small linear/branched/merged sample for graph previews.
    static var previewSamples: [GraphRowLayout] {
        [
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [],
                lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                mergesIn: [],
                mergesOut: [LaneOccupation(lane: 1, branchId: 1)],
                totalLanes: 2, isMerge: false
            ),
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                mergesIn: [], mergesOut: [],
                totalLanes: 2, isMerge: false
            ),
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [LaneOccupation(lane: 0, branchId: 0), LaneOccupation(lane: 1, branchId: 1)],
                lanesAtBottom: [LaneOccupation(lane: 0, branchId: 0)],
                mergesIn: [LaneOccupation(lane: 1, branchId: 1)],
                mergesOut: [],
                totalLanes: 2, isMerge: true
            ),
            GraphRowLayout(
                commitLane: 0, commitBranchId: 0,
                lanesAtTop: [LaneOccupation(lane: 0, branchId: 0)],
                lanesAtBottom: [],
                mergesIn: [], mergesOut: [],
                totalLanes: 1, isMerge: false
            ),
        ]
    }
}

extension ToastMessage {
    static let previewOk    = ToastMessage(message: "Pushed 7 commits to origin/main", kind: .ok)
    static let previewInfo  = ToastMessage(message: "Fetching…", kind: .info)
    static let previewWarn  = ToastMessage(message: "Stash conflict — review", kind: .warn)
    static let previewError = ToastMessage(message: "Push rejected (non fast-forward)", kind: .error)
}

extension CommandPaletteItem {
    @MainActor
    static var previewSamples: [CommandPaletteItem] {
        CommandPaletteBuilder.build(
            repositories: Repository.previewSamples,
            branches: GitRef.previewSamples,
            commits: Commit.previewSamples,
            workingFiles: WorkingCopyStatus.preview.files
        )
    }
}
