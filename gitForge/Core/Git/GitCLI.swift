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

        let startTime = Date()
        let argsString = args.joined(separator: " ")
        Self.logger.debug("→ git \(argsString, privacy: .public)")

        do {
            try process.run()
        } catch {
            Self.logger.error("git \(argsString, privacy: .public) launch failed: \(error.localizedDescription, privacy: .public)")
            throw GitError.launchFailed(error.localizedDescription)
        }

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
        let stderr = String(data: stderrBytes, encoding: .utf8) ?? ""

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
