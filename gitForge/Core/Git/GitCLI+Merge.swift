import Foundation

enum MergeState: Sendable, Equatable {
    case clean
    case merging
    case rebasing

    var isInProgress: Bool { self != .clean }
}

extension GitCLI {
    /// Inspect the `.git` directory to figure out whether a merge or rebase
    /// is currently in progress.
    func mergeState() async -> MergeState {
        let gitDir = workingDirectory.appendingPathComponent(".git")
        let fm = FileManager.default
        if fm.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path(percentEncoded: false)) {
            return .merging
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path(percentEncoded: false))
            || fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path(percentEncoded: false)) {
            return .rebasing
        }
        return .clean
    }

    /// Files currently in `unmerged` state (`U` in porcelain v2).
    func unmergedPaths() async throws -> [String] {
        let result = try await run(["diff", "--name-only", "--diff-filter=U"])
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func mergeAbort() async throws {
        _ = try await run(["merge", "--abort"])
    }

    func mergeContinue() async throws {
        _ = try await run(["merge", "--continue"])
    }

    func rebaseAbort() async throws {
        _ = try await run(["rebase", "--abort"])
    }

    func rebaseContinue() async throws {
        _ = try await run(["rebase", "--continue"])
    }

    /// `git merge <branch> [--no-ff] [--squash] [-m message]`. Throws on
    /// conflicts — caller should refresh conflict state and route the user
    /// to the conflict resolver.
    func merge(branch: String, noFastForward: Bool = false, squash: Bool = false, message: String? = nil) async throws {
        var args: [String] = ["merge"]
        if noFastForward { args.append("--no-ff") }
        if squash        { args.append("--squash") }
        if let message {
            args.append(contentsOf: ["-m", message])
        }
        args.append(branch)
        _ = try await run(args)
    }

    /// `git rebase <upstream>`. Throws on conflicts.
    func rebase(onto upstream: String) async throws {
        _ = try await run(["rebase", upstream])
    }

    /// Stages a path so git knows the conflict is resolved.
    func markResolved(path: String) async throws {
        _ = try await run(["add", "--", path])
    }
}
