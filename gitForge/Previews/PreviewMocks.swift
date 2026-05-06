import Foundation

/// Sample data for redesigned views (`PullsView`, `ConflictView`, `BlameView`,
/// `TerminalView`, …). Lives only in the development asset folder.

extension PullRequest {
    static let previewSamples: [PullRequest] = [
        PullRequest(id: 248, title: "Wire commit-graph virtualizer to commit store",  author: "mvelez",  status: .open,   reviews: 1, checks: .pass,    branch: "feat/commit-graph", target: "main", when: "2h"),
        PullRequest(id: 247, title: "feat(diff): word-level intra-line highlight",    author: "rtanaka", status: .open,   reviews: 0, checks: .running, branch: "feat/conflict-ui",  target: "main", when: "6h"),
        PullRequest(id: 246, title: "fix: diff scroll resets on stage",               author: "asingh",  status: .review, reviews: 2, checks: .pass,    branch: "fix/diff-scroll",   target: "main", when: "1d"),
        PullRequest(id: 245, title: "chore(deps): tauri 1.6 → 1.7",                   author: "mvelez",  status: .merged, reviews: 2, checks: .pass,    branch: "chore/tauri",       target: "main", when: "2d"),
        PullRequest(id: 244, title: "docs: add CONTRIBUTING.md and CODEOWNERS",       author: "lpark",   status: .merged, reviews: 1, checks: .pass,    branch: "docs/contrib",      target: "main", when: "5h"),
    ]
}

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

extension BlameGroup {
    static let previewSamples: [BlameGroup] = [
        BlameGroup(sha: "1e9c3d2", author: "M. Vélez", when: "5d", lines: [
            BlameLine(number: 1, text: "export type Lane = { col: number; color: string }"),
            BlameLine(number: 2, text: ""),
            BlameLine(number: 3, text: "export function layoutLanes(commits: Commit[]): Lane[] {"),
        ], laneColorHex: 0x7c5cff),
        BlameGroup(sha: "4471a09", author: "L. Park", when: "4d", lines: [
            BlameLine(number: 4, text: "  const lanes: Lane[] = []"),
            BlameLine(number: 5, text: "  const seen = new Map<string, number>()"),
        ], laneColorHex: 0x56b497),
        BlameGroup(sha: "2c7e4b0", author: "M. Vélez", when: "1h", lines: [
            BlameLine(number: 6, text: "  let nextCol = 0"),
            BlameLine(number: 7, text: ""),
            BlameLine(number: 8, text: "  for (const c of commits) {"),
        ], laneColorHex: 0xff7e6b),
        BlameGroup(sha: "8b1d99e", author: "M. Vélez", when: "12m", lines: [
            BlameLine(number: 9,  text: "    const col = seen.get(c.sha) ?? nextCol++"),
            BlameLine(number: 10, text: "    lanes[col] ??= { col, color: laneColor(col) }"),
            BlameLine(number: 11, text: "    for (const p of c.parents) seen.set(p.sha, col)"),
        ], laneColorHex: 0xdda44b),
        BlameGroup(sha: "4471a09", author: "L. Park", when: "4d", lines: [
            BlameLine(number: 12, text: "  }"),
            BlameLine(number: 13, text: ""),
            BlameLine(number: 14, text: "  return lanes"),
            BlameLine(number: 15, text: "}"),
        ], laneColorHex: 0x56b497),
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
