import Foundation
import os

actor GitCLI {
    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "git")

    let workingDirectory: URL
    private let executablePath: String

    init(workingDirectory: URL, executablePath: String = "/usr/bin/env") {
        self.workingDirectory = workingDirectory
        self.executablePath = executablePath
    }

    @discardableResult
    func run(_ args: [String]) async throws -> GitResult {
        let workingDirectoryPath = workingDirectory.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: workingDirectoryPath) else {
            throw GitError.invalidWorkingDirectory(workingDirectory)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = ["git"] + args
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        // Four guards to keep git from hanging on input we can't provide:
        //   • GIT_TERMINAL_PROMPT=0 — no stdin prompt for HTTPS credentials.
        //   • GIT_ASKPASS=/usr/bin/true — overrides any GUI askpass that
        //     `core.askPass` config or other tooling (GitHub CLI, third-party
        //     helpers) might have set. Without this, a configured askpass can
        //     pop a hidden dialog and block forever waiting on it. `true`
        //     returns an empty string; git treats it as "no credentials" and
        //     either uses what `credential.helper` provided or fails fast.
        //   • GIT_SSH_COMMAND with BatchMode=yes — ssh refuses to prompt for
        //     a passphrase when the key isn't unlocked in the agent / Keychain.
        //   • GIT_EDITOR=/usr/bin/true — keeps merge/pull-merge/rebase from
        //     trying to open vi for a commit message; defaults are accepted.
        // Credential helpers (osxkeychain, GitHub CLI's gh-credential…) still
        // run first via `credential.helper`; these env vars only suppress the
        // fallbacks that would otherwise block on a TTY or GUI we can't drive.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        if environment["GIT_SSH_COMMAND"] == nil {
            environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        }
        environment["GIT_EDITOR"] = "/usr/bin/true"
        process.environment = environment

        let startTime = Date()
        let argsString = args.joined(separator: " ")
        // Resolve once per invocation so the watchdog and the synthesized
        // timeout-message use a consistent value even if the user flips
        // the setting mid-fetch.
        let timeout = TimeInterval(AppTheme.persistedGitTimeoutSeconds())
        Self.logger.debug("→ git \(argsString, privacy: .public)")

        do {
            try process.run()
        } catch {
            Self.logger.error("git \(argsString, privacy: .public) launch failed: \(error.localizedDescription, privacy: .public)")
            throw GitError.launchFailed(error.localizedDescription)
        }

        // Watchdog. If a command doesn't finish within `timeout`, kill it.
        // Local commands are milliseconds; remote commands are seconds. Anything
        // past the timeout means the subprocess is stuck — dead network,
        // askpass deadlock, misbehaving hook — and we'd rather surface a clean
        // failure than leave the user staring at a frozen spinner. SIGTERM
        // first, SIGKILL after a grace window in case git ignores the soft
        // signal. Default 60s, configurable from Settings → Behavior.
        let watchdog = Task { [process, argsString, timeout] in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled, process.isRunning else { return }
            Self.logger.error("watchdog: terminating `git \(argsString, privacy: .public)` after \(timeout, privacy: .public)s")
            process.terminate()
            try? await Task.sleep(for: .milliseconds(500))
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        defer { watchdog.cancel() }

        // Drain pipes and wait for exit concurrently so the child process
        // never blocks on a full pipe buffer (~64KB on Darwin).
        async let stdoutData = Self.readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData = Self.readToEnd(stderrPipe.fileHandleForReading)
        async let exitWait: Void = Self.waitForExit(process)

        let stdoutBytes = await stdoutData
        let stderrBytes = await stderrData
        _ = await exitWait

        let duration = Date().timeIntervalSince(startTime)
        let stdout = String(data: stdoutBytes, encoding: .utf8) ?? ""
        let capturedStderr = String(data: stderrBytes, encoding: .utf8) ?? ""
        let stderr: String = {
            // Watchdog killed us → captured stderr is usually empty and the
            // generic "exit 15 / no message" toast is useless. Synthesize a
            // message that routes through `RemoteFailure(stderr:)` as `.network`.
            let trimmed = capturedStderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty,
               process.terminationReason == .uncaughtSignal,
               duration >= timeout {
                return "connection timed out after \(Int(timeout))s — the remote may be unreachable, or git is stuck on something the app can't drive non-interactively."
            }
            return capturedStderr
        }()

        let result = GitResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: process.terminationStatus,
            duration: duration
        )

        let durationMs = String(format: "%.0f", duration * 1000)
        if result.isSuccess {
            Self.logger.info("✓ git \(argsString, privacy: .public) (\(durationMs, privacy: .public) ms)")
        } else {
            let trimmedStderr = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            Self.logger.error("✗ git \(argsString, privacy: .public) exited \(result.exitCode) in \(durationMs, privacy: .public) ms: \(trimmedStderr, privacy: .public)")
            throw GitError.commandFailed(
                args: args,
                exitCode: result.exitCode,
                stderr: stderr
            )
        }

        return result
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached {
            (try? handle.readToEnd()) ?? Data()
        }.value
    }

    private static func waitForExit(_ process: Process) async {
        await Task.detached {
            process.waitUntilExit()
        }.value
    }
}
