import Foundation
import os

actor GitCLI {
    static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "git")

    /// Inserted before any user-controlled ref / SHA / branch / URL so a value
    /// starting with `--` can't be reinterpreted by git as a flag (the
    /// CVE-2017-1000117 family). Distinct from `--`, which separates revisions
    /// from paths. Available since git 2.24 (Nov 2019).
    static let endOfOptions = "--end-of-options"

    /// Appended to every command whose patch / name-status output we parse.
    /// The user's own config otherwise leaks in: `color.diff=always` injects
    /// ANSI escapes even into a pipe (and `-c color.ui=false` doesn't
    /// override the more specific key), and `diff.external` replaces the
    /// unified diff with whatever the external tool prints.
    static let diffOutputFlags = ["--no-color", "--no-ext-diff"]

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

        let process = GitProcess.make(arguments: args,
                                      workingDirectory: workingDirectory,
                                      executablePath: executablePath)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()
        // Logged form. Strips the userinfo segment from any URL-shaped argv so
        // a token embedded in `https://oauth2:TOKEN@host/...` doesn't survive
        // into Console / sysdiagnose. Same redaction is applied to stderr.
        let safeArgsString = Self.redacted(args.joined(separator: " "))
        // Resolve once per invocation so the watchdog and the synthesized
        // timeout message use a consistent value even if the user flips the
        // setting mid-fetch.
        let watchdog = GitWatchdog(timeout: TimeInterval(GitPreferences.gitTimeoutSeconds))
        if Diagnostics.traceGitCommands {
            Self.logger.debug("→ git \(safeArgsString, privacy: .public)")
        }

        let exit: ProcessExit
        do {
            exit = try GitProcess.start(process)
        } catch {
            Self.logger.error("git \(safeArgsString, privacy: .public) launch failed: \(error.localizedDescription, privacy: .public)")
            throw GitError.launchFailed(error.localizedDescription)
        }

        // Resets on every chunk read from stdout or stderr. A push of a large
        // pack against a slow upload isn't killed because git keeps emitting
        // progress to stderr.
        watchdog.start(watching: process, label: safeArgsString, logger: Self.logger)
        defer { watchdog.stop() }

        return try await withTaskCancellationHandler {
            // Drain pipes and wait for exit concurrently so the child process
            // never blocks on a full pipe buffer (~64KB on Darwin). Capped
            // so a runaway `git log -p` / `diff` can't OOM the app: when the
            // cap trips, we terminate the subprocess and surface
            // `outputTooLarge` instead of letting Data grow unbounded.
            async let stdoutResult = Self.readCapped(stdoutPipe.fileHandleForReading, cap: Self.stdoutByteCap, onProgress: { watchdog.tick() }, onOverflow: { process.terminate() })
            async let stderrResult = Self.readCapped(stderrPipe.fileHandleForReading, cap: Self.stderrByteCap, onProgress: { watchdog.tick() }, onOverflow: nil)
            async let exitWait: Void = exit.wait()

            let (stdoutBytes, stdoutTruncated) = await stdoutResult
            let (stderrBytes, _) = await stderrResult
            _ = await exitWait

            // Caller cancelled → the onCancel handler SIGTERM'd the process.
            // Surface CancellationError so callers can distinguish user-cancel
            // from a real `commandFailed`, mirroring `clone`'s contract.
            if Task.isCancelled, !watchdog.timedOut, process.terminationReason == .uncaughtSignal {
                throw CancellationError()
            }

            if stdoutTruncated {
                Self.logger.error("✗ git \(safeArgsString, privacy: .public) exceeded \(Self.stdoutByteCap / 1_048_576)MB cap, terminated")
                throw GitError.outputTooLarge(consumed: stdoutBytes.count, cap: Self.stdoutByteCap)
            }

            let duration = Date().timeIntervalSince(startTime)
            let stdout = GitProcess.decode(stdoutBytes)
            let capturedStderr = GitProcess.decode(stderrBytes)
            // Watchdog killed us → captured stderr is usually empty and the
            // generic "exit 15 / no message" toast is useless. Synthesize a
            // message that routes through `RemoteFailure(stderr:)` as `.network`.
            let stderr: String = {
                let trimmed = capturedStderr.trimmingCharacters(in: .whitespacesAndNewlines)
                return watchdog.timedOut && trimmed.isEmpty ? watchdog.timeoutMessage : capturedStderr
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
            // `Process` is Sendable and `terminate()` is safe from any thread.
            process.terminate()
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
        await GitProcess.offPool {
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
        }
    }
}
