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
        async let autoFetch      = get("gitForge.autoFetchInterval")

        return await GitGlobalConfig(
            identity: GitIdentity(name: name, email: email),
            defaultBranch: defaultBranch,
            pullStrategy: pullStrategy,
            signingKey: signingKey,
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
            let result = try await runGlobal(["config", "--global", "--get", key], allowFailure: true)
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            return nil
        }
    }

    private func set(_ key: String, value: String) async throws {
        _ = try await runGlobal(["config", "--global", key, value], allowFailure: false)
    }

    /// Best-effort `git config --unset`. Exit code 5 means "the key wasn't
    /// there to begin with" — we treat that as success.
    private func unset(_ key: String) async throws {
        _ = try await runGlobal(["config", "--global", "--unset", key], allowFailure: true)
    }

    /// `git config --global` works against `$HOME`, not the cwd, but Process
    /// still needs an existing working directory. Use the user's home.
    private func runGlobal(_ args: [String], allowFailure: Bool) async throws -> GitResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        async let stdoutData: Data = readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData: Data = readToEnd(stderrPipe.fileHandleForReading)
        async let exitWait: Void = waitForExit(process)

        let stdoutBytes = await stdoutData
        let stderrBytes = await stderrData
        _ = await exitWait

        let stdout = String(data: stdoutBytes, encoding: .utf8) ?? ""
        let stderr = String(data: stderrBytes, encoding: .utf8) ?? ""

        let result = GitResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            duration: 0
        )

        if !result.isSuccess && !allowFailure {
            throw GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: stderr)
        }
        return result
    }

    private func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached { (try? handle.readToEnd()) ?? Data() }.value
    }

    private func waitForExit(_ process: Process) async {
        await Task.detached { process.waitUntilExit() }.value
    }
}
