import Foundation
import os

extension GitCLI {
    /// Like `run`, but hands stdout to `onOutput` chunk by chunk as git
    /// writes it instead of buffering it, so a long command (blame of a big
    /// file) shows progress. `onOutput` runs on a background thread, one
    /// chunk at a time, in order. The returned `GitResult.stdout` is empty.
    ///
    /// Same contract as `run` otherwise: the idle watchdog (reset by every
    /// chunk), `CancellationError` when the task is cancelled, and
    /// `GitError.commandFailed` on a non-zero exit.
    @discardableResult
    func runStreaming(_ args: [String], onOutput: @escaping @Sendable (Data) -> Void) async throws -> GitResult {
        guard FileManager.default.fileExists(atPath: workingDirectory.path(percentEncoded: false)) else {
            throw GitError.invalidWorkingDirectory(workingDirectory)
        }
        let process = GitProcess.make(arguments: args, workingDirectory: workingDirectory,
                                      executablePath: executablePath)
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startTime = Date()
        let safeArgsString = Self.redacted(args.joined(separator: " "))
        let kind = GitCommandKind(arguments: args)
        let watchdog = GitWatchdog(timeout: kind.idleTimeout(configured: TimeInterval(configuredTimeoutSeconds())),
                                   kind: kind)
        let exit: ProcessExit
        do {
            exit = try GitProcess.start(process)
        } catch {
            Self.logger.error("git \(safeArgsString, privacy: .public) launch failed: \(error.localizedDescription, privacy: .public)")
            throw GitError.launchFailed(error.localizedDescription)
        }
        watchdog.start(watching: process, label: safeArgsString, logger: Self.logger)
        defer { watchdog.stop() }

        return try await withTaskCancellationHandler {
            let stdoutHandle = stdoutPipe.fileHandleForReading
            async let streamed: Void = GitProcess.offPool {
                while let chunk = try? stdoutHandle.read(upToCount: 65_536), !chunk.isEmpty {
                    watchdog.tick()
                    onOutput(chunk)
                }
            }
            async let stderrBytes = GitProcess.readToEnd(stderrPipe.fileHandleForReading)
            async let exitWait: Void = exit.wait()
            _ = await streamed
            let stderrData = await stderrBytes
            _ = await exitWait

            if Task.isCancelled, !watchdog.timedOut, process.terminationReason == .uncaughtSignal {
                throw CancellationError()
            }
            let captured = GitProcess.decode(stderrData.prefix(Self.stderrByteCap))
            let trimmed = captured.trimmingCharacters(in: .whitespacesAndNewlines)
            let stderr = watchdog.timedOut && trimmed.isEmpty ? watchdog.timeoutMessage : captured
            let duration = Date().timeIntervalSince(startTime)
            let result = GitResult(stdout: "", stderr: stderr, exitCode: process.terminationStatus, duration: duration)
            guard result.isSuccess else {
                Self.logger.error("✗ git \(safeArgsString, privacy: .public) exited \(result.exitCode): \(Self.redacted(trimmed), privacy: .public)")
                AppLog.shared.gitFailure(args: args, exitCode: result.exitCode, stderr: stderr, duration: duration)
                throw GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: stderr)
            }
            return result
        } onCancel: {
            process.terminate()
        }
    }
}
