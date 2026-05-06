import Foundation

/// Per-commit operations layered on top of `GitCLI` — cherry-pick, revert,
/// reset. Conflicts surface the same way as merge/rebase: the command throws,
/// the caller refreshes conflict state, and the user is routed to the
/// resolver UI.
extension GitCLI {
    func cherryPick(sha: String, mainline: Int? = nil) async throws {
        var args: [String] = ["cherry-pick"]
        if let mainline { args += ["-m", String(mainline)] }
        args.append(sha)
        _ = try await run(args)
    }

    func cherryPickAbort() async throws {
        _ = try await run(["cherry-pick", "--abort"])
    }

    func cherryPickContinue() async throws {
        _ = try await run(["cherry-pick", "--continue"])
    }

    /// Default uses `--no-edit` so the auto-generated revert message is kept.
    /// `mainline` is required when reverting a merge commit (1 is `HEAD`).
    func revert(sha: String, mainline: Int? = nil, noCommit: Bool = false) async throws {
        var args: [String] = ["revert", "--no-edit"]
        if let mainline { args += ["-m", String(mainline)] }
        if noCommit     { args.append("--no-commit") }
        args.append(sha)
        _ = try await run(args)
    }

    enum ResetMode: String, Sendable, CaseIterable, Identifiable {
        case soft, mixed, hard
        var id: String { rawValue }
        var flag: String { "--\(rawValue)" }
        var label: String {
            switch self {
            case .soft:  return "Soft (keep changes staged)"
            case .mixed: return "Mixed (keep changes unstaged)"
            case .hard:  return "Hard (discard everything)"
            }
        }
    }

    func reset(to sha: String, mode: ResetMode) async throws {
        _ = try await run(["reset", mode.flag, sha])
    }
}
