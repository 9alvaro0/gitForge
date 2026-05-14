import Foundation

extension GitCLI {
    func status() async throws -> WorkingCopyStatus {
        // `-z` switches record + rename separators to NUL. Without it, paths
        // containing literal `\n` or `\t` would either be C-quoted (which we
        // never decode) or break the line-based split outright.
        let result = try await run(["status", "--porcelain=v2", "-u", "-z"])
        return WorkingCopyStatus(files: Self.parseStatus(result.stdout))
    }

    static func parseStatus(_ stdout: String) -> [WorkingCopyFile] {
        // Records separated by NUL (porcelain v2 + -z). For renamed/copied
        // entries (type 2) the path and origPath are themselves separated by
        // NUL, so a type-2 record occupies two consecutive array elements.
        let records = stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        var files: [WorkingCopyFile] = []
        var i = 0
        while i < records.count {
            let record = records[i]
            guard let first = record.first else { i += 1; continue }
            switch first {
            case "1":
                let fields = record.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                if fields.count >= 9,
                   let f = makeFile(xy: String(fields[1]), path: String(fields[8]), originalPath: nil) {
                    files.append(f)
                }
                i += 1
            case "2":
                // Type 2 has one extra field (`R100`/`C100` rename score)
                // before the path, so the path lives at fields[9].
                let fields = record.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                let orig = (i + 1 < records.count) ? records[i + 1] : ""
                if fields.count >= 10,
                   let f = makeFile(xy: String(fields[1]), path: String(fields[9]), originalPath: orig) {
                    files.append(f)
                }
                // Consume the path AND the origPath record.
                i += 2
            case "?":
                let path = String(record.dropFirst(2))
                files.append(WorkingCopyFile(path: path, stagedStatus: .unmodified, unstagedStatus: .untracked, originalPath: nil))
                i += 1
            case "!":
                // Ignored entry — not displayed.
                i += 1
            case "u":
                let fields = record.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                if fields.count >= 11 {
                    files.append(WorkingCopyFile(path: String(fields[10]),
                                                 stagedStatus: .unmerged,
                                                 unstagedStatus: .unmerged,
                                                 originalPath: nil))
                }
                i += 1
            default:
                i += 1
            }
        }
        return mergeUnstagedRenames(files)
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
