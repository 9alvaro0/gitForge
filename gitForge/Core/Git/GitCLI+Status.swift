import Foundation

extension GitCLI {
    func status() async throws -> WorkingCopyStatus {
        let result = try await run(["status", "--porcelain=v2", "-u"])
        return WorkingCopyStatus(files: Self.parseStatus(result.stdout))
    }

    static func parseStatus(_ stdout: String) -> [WorkingCopyFile] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            parseLine(String(line))
        }
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
