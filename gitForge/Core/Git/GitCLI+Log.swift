import Foundation

extension GitCLI {
    private static let logSeparator = "\u{1F}"
    private static let logFormat = "%H\u{1F}%P\u{1F}%an\u{1F}%ae\u{1F}%aI\u{1F}%s"

    func log(branch: String? = nil, limit: Int = 200, skip: Int = 0) async throws -> [Commit] {
        var args: [String] = ["log", "--topo-order", "--format=\(Self.logFormat)", "-n", String(limit)]
        if skip > 0 {
            args.append("--skip")
            args.append(String(skip))
        }
        if let branch {
            args.append(branch)
        }
        let result = try await run(args)
        return Self.parseLog(result.stdout)
    }

    static func parseLog(_ stdout: String) -> [Commit] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withTimeZone]
        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]

        return stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: Character(logSeparator), omittingEmptySubsequences: false)
            guard parts.count >= 6 else { return nil }
            let sha = String(parts[0])
            let parents = parts[1].isEmpty ? [] : parts[1].split(separator: " ").map { String($0) }
            let authorName = String(parts[2])
            let authorEmail = String(parts[3])
            let dateString = String(parts[4])
            let date = formatter.date(from: dateString) ?? fallback.date(from: dateString) ?? Date()
            let subject = parts[5...].joined(separator: logSeparator)
            return Commit(
                sha: sha,
                parentShas: parents,
                authorName: authorName,
                authorEmail: authorEmail,
                authorDate: date,
                subject: subject
            )
        }
    }

    func commitDetail(for commit: Commit) async throws -> CommitDetail {
        async let bodyResult = run(["log", "-1", commit.sha, "--format=%B"])
        async let filesResult = run(["diff-tree", "--no-commit-id", "--name-status", "-r", commit.sha])
        let body = try await bodyResult
        let files = try await filesResult
        return CommitDetail(
            commit: commit,
            fullMessage: body.stdout,
            files: Self.parseNameStatus(files.stdout)
        )
    }

    static func parseNameStatus(_ stdout: String) -> [CommitFileChange] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard let raw = parts.first else { return nil }
            let code = String(raw)
            let firstChar = code.first.map(String.init) ?? ""

            switch firstChar {
            case "A":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .added)
            case "M":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .modified)
            case "D":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .deleted)
            case "R":
                guard parts.count >= 3 else { return nil }
                return CommitFileChange(path: String(parts[2]), status: .renamed(from: String(parts[1])))
            case "C":
                guard parts.count >= 3 else { return nil }
                return CommitFileChange(path: String(parts[2]), status: .copied(from: String(parts[1])))
            case "T":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .typeChanged)
            case "U":
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .unmerged)
            default:
                guard parts.count >= 2 else { return nil }
                return CommitFileChange(path: String(parts[1]), status: .unknown(code))
            }
        }
    }

    func diff(sha: String, file: String) async throws -> String {
        let parentRef = "\(sha)^"
        let result = try? await run(["diff", parentRef, sha, "--", file])
        if let result {
            return result.stdout
        }
        // Initial commit has no parent; use empty tree
        let emptyTree = "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
        let fallback = try await run(["diff", emptyTree, sha, "--", file])
        return fallback.stdout
    }
}
