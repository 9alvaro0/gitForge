import Foundation
import os

/// Reads (and writes) `git config --global` keys without requiring a repository.
/// Stateless on purpose — every call shells out fresh; the values aren't cached
/// here, so callers (AppState) decide when to refresh.
actor GitGlobalConfigReader {
    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "git-config")

    static let shared = GitGlobalConfigReader()

    func read() async -> GitGlobalConfig {
        async let name           = get("user.name")
        async let email          = get("user.email")
        async let defaultBranch  = get("init.defaultBranch")
        async let pullStrategy   = pullStrategyFromConfig()
        async let signingKey     = get("user.signingkey")
        async let signCommits    = get("commit.gpgsign")
        async let autoFetch      = get("gitForge.autoFetchInterval")

        return await GitGlobalConfig(
            identity: GitIdentity(name: name, email: email),
            defaultBranch: defaultBranch,
            pullStrategy: pullStrategy,
            signingKey: signingKey,
            signCommits: signCommits.flatMap(Self.parseBool),
            autoFetchInterval: autoFetch.flatMap(Int.init)
        )
    }

    func setName(_ name: String) async throws {
        try await set("user.name", value: name)
    }

    func setEmail(_ email: String) async throws {
        try await set("user.email", value: email)
    }

    func setSigningKey(_ key: String?) async throws {
        if let key, !key.isEmpty {
            try await set("user.signingkey", value: key)
        } else {
            try await unset("user.signingkey")
        }
    }

    /// Writes `commit.gpgsign true` when on, otherwise unsets the key so
    /// git falls back to its default (off). Avoids leaving a stale `false`
    /// behind, which would override a future repo-level override.
    func setSignCommits(_ enabled: Bool) async throws {
        if enabled {
            try await set("commit.gpgsign", value: "true")
        } else {
            try await unset("commit.gpgsign")
        }
    }

    /// Parses git config bool values — `true`/`false`, `1`/`0`, `yes`/`no`,
    /// `on`/`off`. Anything else is treated as nil (unrecognised).
    private static func parseBool(_ raw: String) -> Bool? {
        switch raw.lowercased() {
        case "true", "1", "yes", "on":   return true
        case "false", "0", "no", "off":  return false
        default:                          return nil
        }
    }

    func setDefaultBranch(_ name: String?) async throws {
        if let name, !name.isEmpty {
            try await set("init.defaultBranch", value: name)
        } else {
            try await unset("init.defaultBranch")
        }
    }

    /// Three valid pull strategies in git: `rebase` / `merge` / `ff-only`.
    /// `nil` removes the override and falls back to git's default.
    func setPullStrategy(_ strategy: String?) async throws {
        // Always clear both keys first so we don't leave conflicting state.
        try await unset("pull.rebase")
        try await unset("pull.ff")
        switch strategy {
        case "rebase":  try await set("pull.rebase", value: "true")
        case "merge":   try await set("pull.rebase", value: "false")
        case "ff-only": try await set("pull.ff", value: "only")
        default:        break // nil / unknown → leave both unset
        }
    }

    /// Auto-fetch interval in seconds (writes a custom `gitForge.*` key so we
    /// don't pollute standard git keys). Pass `nil` to disable.
    func setAutoFetchInterval(_ seconds: Int?) async throws {
        if let seconds, seconds > 0 {
            try await set("gitForge.autoFetchInterval", value: String(seconds))
        } else {
            try await unset("gitForge.autoFetchInterval")
        }
    }

    // MARK: private

    private func pullStrategyFromConfig() async -> String? {
        if let rebase = await get("pull.rebase"), !rebase.isEmpty {
            return rebase == "true" ? "rebase" : "merge"
        }
        if let ff = await get("pull.ff"), !ff.isEmpty {
            return ff == "only" ? "ff-only" : nil
        }
        return nil
    }

    private func get(_ key: String) async -> String? {
        do {
            // Exit 1 = key not set; anything else is logged by `runGlobal`.
            let result = try await runGlobal(["config", "--global", "--get", key], allowedExitCodes: [0, 1])
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    private func set(_ key: String, value: String) async throws {
        _ = try await runGlobal(["config", "--global", key, value])
    }

    /// `git config --unset`. Exit code 5 means "the key wasn't there to
    /// begin with" — the desired post-state, so it counts as success. Any
    /// other failure (locked or unwritable `~/.gitconfig`) throws instead of
    /// pretending the setting was cleared.
    private func unset(_ key: String) async throws {
        _ = try await runGlobal(["config", "--global", "--unset", key], allowedExitCodes: [0, 5])
    }

    /// `git config --global` works against `$HOME`, not the cwd, but Process
    /// still needs an existing working directory. Use the user's home.
    private func runGlobal(_ args: [String], allowedExitCodes: Set<Int32> = [0]) async throws -> GitResult {
        let process = GitProcess.make(arguments: args,
                                      workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let exit: ProcessExit
        do {
            exit = try GitProcess.start(process)
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        async let stdoutData: Data = GitProcess.readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData: Data = GitProcess.readToEnd(stderrPipe.fileHandleForReading)
        async let exitWait: Void = exit.wait()

        let stdout = GitProcess.decode(await stdoutData)
        let stderr = GitProcess.decode(await stderrData)
        _ = await exitWait

        let result = GitResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            duration: 0
        )

        guard allowedExitCodes.contains(result.exitCode) else {
            Self.logger.error("git \(args.joined(separator: " "), privacy: .public) exited \(result.exitCode): \(stderr, privacy: .public)")
            throw GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: stderr)
        }
        return result
    }
}
