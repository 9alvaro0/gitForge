import Foundation
import os

actor GitCLI {
    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "git")

    /// Inserted before any user-controlled ref / SHA / branch / URL so a value
    /// starting with `--` can't be reinterpreted by git as a flag (the
    /// CVE-2017-1000117 family). Distinct from `--`, which separates revisions
    /// from paths. Available since git 2.24 (Nov 2019).
    static let endOfOptions = "--end-of-options"

    /// Hard cap on stdout we'll buffer per command. Above this we kill the
    /// subprocess and throw `outputTooLarge` — protects the app from OOM on
    /// pathological diffs / `git log -p` calls without forcing every caller
    /// to think about streaming. 200MB chosen empirically: covers real-world
    /// monorepo diffs comfortably (~10MB tops) while still tripping before
    /// macOS jetsam decides to kill us.
    static let stdoutByteCap = 200 * 1_048_576
    /// stderr is informational; if a command emits >1MB of stderr something
    /// has already gone very wrong and we don't need to keep more of it.
    static let stderrByteCap = 1_048_576

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
        // Global flags applied to every git invocation:
        //   • -c core.quotePath=false: emit paths verbatim instead of the
        //     C-escaped `"caf\303\251.txt"` form. Without this the porcelain
        //     parser keeps the literal escapes and a subsequent `git add --`
        //     fails because the pathspec doesn't match any file on disk.
        //   • -c core.precomposeUnicode=true: macOS git default is already
        //     true, but forcing it shields users who set it to false in their
        //     global config (NFD-vs-NFC mismatches break Swift `String == String`
        //     comparisons in the VM).
        //
        // NOTE: `--no-optional-locks` was here too in an earlier pass to
        // avoid two reads colliding on `.git/index`. It also prevents
        // `git status` from refreshing the index, which surfaces as
        // false-positive `M` entries when an editor rewrites a file with
        // the same content (mtime changes, content doesn't). Removed —
        // the watcher's own serialisation (isMutating + suspend / debounce)
        // already covers the collision case in practice.
        process.arguments = [
            "git",
            "-c", "core.quotePath=false",
            "-c", "core.precomposeUnicode=true",
        ] + args
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
        // Pin git's output language so RemoteFailure.from (which matches on
        // English substrings like "authentication failed") categorises
        // reliably. Otherwise a user with LANG=es_ES sees `.other` + raw
        // stderr — which leaks tokens when the URL embeds them.
        environment["LC_ALL"] = "C"
        process.environment = environment

        let startTime = Date()
        // Logged form. Strips the userinfo segment from any URL-shaped argv so
        // a token embedded in `https://oauth2:TOKEN@host/...` doesn't survive
        // into Console / sysdiagnose. Same redaction is applied to stderr.
        let safeArgsString = Self.redacted(args.joined(separator: " "))
        // Resolve once per invocation so the watchdog and the synthesized
        // timeout-message use a consistent value even if the user flips
        // the setting mid-fetch.
        let timeout = TimeInterval(AppTheme.persistedGitTimeoutSeconds())
        if Diagnostics.traceGitCommands {
            Self.logger.debug("→ git \(safeArgsString, privacy: .public)")
        }

        do {
            try process.run()
        } catch {
            Self.logger.error("git \(safeArgsString, privacy: .public) launch failed: \(error.localizedDescription, privacy: .public)")
            throw GitError.launchFailed(error.localizedDescription)
        }

        // Process supports `terminate()` from any thread, so capturing it for
        // the cancel handler is safe.
        let processRef = process

        // Progress-based watchdog. Resets on every chunk read from stdout or
        // stderr; if there's no activity for `timeout` seconds, terminate.
        // A push of a large pack against a slow upload doesn't get killed
        // because git is still emitting progress to stderr (`--progress`
        // implicit on attached terminals; harmless otherwise). DNS hangs and
        // askpass deadlocks die in seconds because nothing flows.
        let progressTimer = ProgressTimer()
        let watchdog = Task { [process, safeArgsString, timeout] in
            while !Task.isCancelled, process.isRunning {
                try? await Task.sleep(for: .seconds(5))
                if progressTimer.elapsed() > timeout {
                    Self.logger.error("watchdog: terminating `git \(safeArgsString, privacy: .public)` after \(timeout, privacy: .public)s without progress")
                    process.terminate()
                    try? await Task.sleep(for: .milliseconds(500))
                    if process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                    }
                    break
                }
            }
        }
        defer { watchdog.cancel() }

        return try await withTaskCancellationHandler {
            // Drain pipes and wait for exit concurrently so the child process
            // never blocks on a full pipe buffer (~64KB on Darwin). Capped
            // so a runaway `git log -p` / `diff` can't OOM the app: when the
            // cap trips, we terminate the subprocess and surface
            // `outputTooLarge` instead of letting Data grow unbounded.
            // onProgress tick lets the watchdog know the subprocess is alive.
            async let stdoutResult = Self.readCapped(stdoutPipe.fileHandleForReading, cap: Self.stdoutByteCap, onProgress: { progressTimer.tick() }, onOverflow: { processRef.terminate() })
            async let stderrResult = Self.readCapped(stderrPipe.fileHandleForReading, cap: Self.stderrByteCap, onProgress: { progressTimer.tick() }, onOverflow: nil)
            async let exitWait: Void = Self.waitForExit(process)

            let (stdoutBytes, stdoutTruncated) = await stdoutResult
            let (stderrBytes, _) = await stderrResult
            _ = await exitWait

            // Caller cancelled → the onCancel handler SIGTERM'd the process.
            // Surface CancellationError so callers can distinguish user-cancel
            // from a real `commandFailed`, mirroring `clone`'s contract.
            if Task.isCancelled, process.terminationReason == .uncaughtSignal {
                throw CancellationError()
            }

            if stdoutTruncated {
                Self.logger.error("✗ git \(safeArgsString, privacy: .public) exceeded \(Self.stdoutByteCap / 1_048_576)MB cap, terminated")
                throw GitError.outputTooLarge(consumed: stdoutBytes.count, cap: Self.stdoutByteCap)
            }

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
                if Diagnostics.traceGitCommands {
                    Self.logger.debug("✓ git \(safeArgsString, privacy: .public) (\(durationMs, privacy: .public) ms)")
                }
            } else {
                let trimmedStderr = Self.redacted(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
                Self.logger.error("✗ git \(safeArgsString, privacy: .public) exited \(result.exitCode) in \(durationMs, privacy: .public) ms: \(trimmedStderr, privacy: .public)")
                throw GitError.commandFailed(
                    args: args,
                    exitCode: result.exitCode,
                    stderr: stderr
                )
            }

            return result
        } onCancel: {
            processRef.terminate()
        }
    }

    /// Replaces `scheme://userinfo@` with `scheme://****@` so embedded
    /// credentials don't survive into Console logs or sysdiagnose. Leaves the
    /// SCP form (`user@host:path`) alone — SSH doesn't carry credentials in
    /// the URL and the username there is part of what the operator is
    /// debugging.
    static func redacted(_ text: String) -> String {
        guard text.contains("://") else { return text }
        let pattern = "://[^@/\\s]+@"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "://****@")
    }

    /// Reads `handle` to EOF, accumulating up to `cap` bytes. Returns the
    /// data plus a flag indicating whether the cap was hit (in which case the
    /// caller should treat the result as truncated). If `onOverflow` is
    /// supplied, it fires the first time the cap trips — used to terminate
    /// the subprocess so a giant `git log -p` doesn't keep streaming
    /// gigabytes into a pipe we'd just discard. `onProgress` fires once per
    /// chunk read so a progress-based watchdog can reset its idle timer.
    private static func readCapped(_ handle: FileHandle,
                                   cap: Int,
                                   onProgress: (@Sendable () -> Void)? = nil,
                                   onOverflow: (@Sendable () -> Void)?) async -> (data: Data, truncated: Bool) {
        await Task.detached {
            var accumulated = Data()
            var truncated = false
            while true {
                let chunk: Data
                do {
                    chunk = try handle.read(upToCount: 65_536) ?? Data()
                } catch {
                    break
                }
                if chunk.isEmpty { break }
                onProgress?()
                if accumulated.count + chunk.count > cap {
                    let remaining = max(0, cap - accumulated.count)
                    if remaining > 0 { accumulated.append(chunk.prefix(remaining)) }
                    truncated = true
                    onOverflow?()
                    // Keep draining to EOF so the writer doesn't block on a
                    // full pipe — discard, don't grow the buffer further.
                    while let drain = try? handle.read(upToCount: 65_536), !drain.isEmpty { }
                    break
                }
                accumulated.append(chunk)
            }
            return (accumulated, truncated)
        }.value
    }

    /// Thread-safe "seconds since last progress signal". Mirrors the helper
    /// inside GitCLI+Clone — duplicated to keep that file self-contained.
    private final class ProgressTimer: @unchecked Sendable {
        private let lock = NSLock()
        private var lastAt = Date()
        func tick() {
            lock.lock(); defer { lock.unlock() }
            lastAt = Date()
        }
        func elapsed() -> TimeInterval {
            lock.lock(); defer { lock.unlock() }
            return Date().timeIntervalSince(lastAt)
        }
    }

    private static func waitForExit(_ process: Process) async {
        await Task.detached {
            process.waitUntilExit()
        }.value
    }
}
