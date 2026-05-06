import Foundation

extension GitCLI {
    func stashes() async throws -> [Stash] {
        let result = try await run(["stash", "list", "--format=%H%x09%gd%x09%gs"])
        return Self.parseStashes(result.stdout)
    }

    static func parseStashes(_ stdout: String) -> [Stash] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let sha = String(parts[0])
            let ref = String(parts[1])
            let subject = String(parts[2])
            guard let openBrace = ref.firstIndex(of: "{"),
                  let closeBrace = ref.firstIndex(of: "}"),
                  closeBrace > ref.index(after: openBrace),
                  let index = Int(ref[ref.index(after: openBrace)..<closeBrace]) else {
                return nil
            }
            return Stash(index: index, sha: sha, subject: subject)
        }
    }

    func stashApply(index: Int, drop: Bool = false) async throws {
        let action = drop ? "pop" : "apply"
        try await run(["stash", action, "stash@{\(index)}"])
    }

    func stashDrop(index: Int) async throws {
        try await run(["stash", "drop", "stash@{\(index)}"])
    }

    func stashPush(message: String? = nil, includeUntracked: Bool = true) async throws {
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message, !message.isEmpty {
            args.append("-m")
            args.append(message)
        }
        try await run(args)
    }
}
