import Foundation

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
