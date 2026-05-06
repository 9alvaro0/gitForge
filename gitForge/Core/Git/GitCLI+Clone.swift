import Foundation
import os

extension GitCLI {
    /// `git clone <url> <destination>`. Doesn't need an existing repo —
    /// runs from `$HOME` so `Process` has a valid cwd. The destination's parent
    /// directory must exist; the leaf is created by git itself.
    static func clone(url: String,
                      destination: URL,
                      branch: String? = nil) async throws {
        var args: [String] = ["clone"]
        if let branch, !branch.isEmpty { args += ["--branch", branch] }
        args += [url, destination.path(percentEncoded: false)]

        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let argsString = args.joined(separator: " ")
        logger.info("→ git \(argsString, privacy: .public)")

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        async let stdoutData: Data = readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData: Data = readToEnd(stderrPipe.fileHandleForReading)
        async let exitWait: Void = waitForExit(process)

        _ = await stdoutData
        let stderrBytes = await stderrData
        _ = await exitWait

        let stderr = String(data: stderrBytes, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            logger.error("✗ git \(argsString, privacy: .public) exited \(process.terminationStatus): \(stderr, privacy: .public)")
            throw GitError.commandFailed(args: args, exitCode: process.terminationStatus, stderr: stderr)
        }
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached { (try? handle.readToEnd()) ?? Data() }.value
    }

    private static func waitForExit(_ process: Process) async {
        await Task.detached { process.waitUntilExit() }.value
    }
}
