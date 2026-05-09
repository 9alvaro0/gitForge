import Foundation

extension GitCLI {
    func status() async throws -> WorkingCopyStatus {
        let result = try await run(["status", "--porcelain=v2", "-u"])
        return WorkingCopyStatus(files: Self.parseStatus(result.stdout))
    }

    static func parseStatus(_ stdout: String) -> [WorkingCopyFile] {
        let raw = stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            parseLine(String(line))
        }
        return mergeUnstagedRenames(raw)
    }

    /// Pairs unstaged `D <old>` entries with `?? <new>` entries that share
    /// the same file basename and fuses them into a single `.renamed` row.
    /// `git status` doesn't surface unstaged renames itself — it only flags
    /// `R` after the move has been staged (similarity is computed against
    /// HEAD's index). The pairing here is a UX reconstruction so a `git mv`
    /// or a Finder-side move shows up as one row, not two.
    ///
    /// Strategy: basename match is ~95%-correct for real-world renames
    /// (paths change, file names rarely do). Multiple deletes or untracked
    /// files sharing a basename are left untouched — we only fuse strict
    /// 1:1 pairs to avoid mis-attribution.
    private static func mergeUnstagedRenames(_ files: [WorkingCopyFile]) -> [WorkingCopyFile] {
        var deletedByBase: [String: [WorkingCopyFile]] = [:]
        var untrackedByBase: [String: [WorkingCopyFile]] = [:]
        for file in files {
            if file.stagedStatus == .unmodified, file.unstagedStatus == .deleted {
                deletedByBase[basename(file.path), default: []].append(file)
            } else if file.stagedStatus == .unmodified, file.unstagedStatus == .untracked {
                untrackedByBase[basename(file.path), default: []].append(file)
            }
        }

        var pairedDeleted: Set<String> = []
        var pairedUntracked: Set<String> = []
        var renames: [WorkingCopyFile] = []
        for (base, deletes) in deletedByBase {
            guard deletes.count == 1,
                  let untrackeds = untrackedByBase[base], untrackeds.count == 1
            else { continue }
            let oldFile = deletes[0]
            let newFile = untrackeds[0]
            pairedDeleted.insert(oldFile.path)
            pairedUntracked.insert(newFile.path)
            renames.append(WorkingCopyFile(
                path: newFile.path,
                stagedStatus: .unmodified,
                unstagedStatus: .renamed,
                originalPath: oldFile.path
            ))
        }

        let kept = files.filter { file in
            !pairedDeleted.contains(file.path) && !pairedUntracked.contains(file.path)
        }
        return kept + renames
    }

    private static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private static func parseLine(_ line: String) -> WorkingCopyFile? {
        guard let first = line.first else { return nil }
        switch first {
        case "1":
            // "1 XY ... <path>"
            let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
            guard fields.count >= 9 else { return nil }
            let xy = String(fields[1])
            let path = String(fields[8])
            return makeFile(xy: xy, path: path, originalPath: nil)
        case "2":
            // "2 XY ... <path>\t<orig>"
            let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
            guard fields.count >= 10 else { return nil }
            let xy = String(fields[1])
            let combined = String(fields[9])
            let parts = combined.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return makeFile(xy: xy, path: String(parts[0]), originalPath: String(parts[1]))
        case "?":
            let path = String(line.dropFirst(2))
            return WorkingCopyFile(path: path, stagedStatus: .unmodified, unstagedStatus: .untracked, originalPath: nil)
        case "!":
            return nil // ignored — not displayed
        case "u":
            // unmerged
            let fields = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
            guard fields.count >= 11 else { return nil }
            let path = String(fields[10])
            return WorkingCopyFile(path: path, stagedStatus: .unmerged, unstagedStatus: .unmerged, originalPath: nil)
        default:
            return nil
        }
    }

    private static func makeFile(xy: String, path: String, originalPath: String?) -> WorkingCopyFile? {
        guard xy.count == 2 else { return nil }
        let staged = WorkingCopyFile.Status(porcelainCode: xy.first!)
        let unstaged = WorkingCopyFile.Status(porcelainCode: xy.last!)
        return WorkingCopyFile(
            path: path,
            stagedStatus: staged,
            unstagedStatus: unstaged,
            originalPath: originalPath
        )
    }
}
