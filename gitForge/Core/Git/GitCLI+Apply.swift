import Foundation
import os

extension GitCLI {
    /// Runs `git apply [--cached] [--reverse]` with `patch` piped through
    /// stdin. Used for hunk-level staging/unstaging.
    func applyPatch(_ patch: String, cached: Bool = true, reverse: Bool = false) async throws {
        var args: [String] = ["apply", "--whitespace=nowarn"]
        if cached  { args.append("--cached") }
        if reverse { args.append("--reverse") }
        args.append("-")

        let workingDirectoryPath = workingDirectory.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: workingDirectoryPath) else {
            throw GitError.invalidWorkingDirectory(workingDirectory)
        }

        let process = Process()
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = workingDirectory
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let argsString = args.joined(separator: " ")
        Self.logger.info("→ git \(argsString, privacy: .public)")

        do {
            try process.run()
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        // Write the patch on a detached task so we can drain pipes concurrently.
        let writeTask = Task.detached {
            if let data = patch.data(using: .utf8) {
                try? stdinPipe.fileHandleForWriting.write(contentsOf: data)
            }
            try? stdinPipe.fileHandleForWriting.close()
        }

        async let stdoutData: Data = readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData: Data = readToEnd(stderrPipe.fileHandleForReading)
        async let exitWait: Void = waitForExit(process)

        _ = await writeTask.value
        _ = await stdoutData
        let stderrBytes = await stderrData
        _ = await exitWait

        let stderr = String(data: stderrBytes, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            Self.logger.error("✗ git \(argsString, privacy: .public) exited \(process.terminationStatus): \(stderr, privacy: .public)")
            throw GitError.commandFailed(args: args, exitCode: process.terminationStatus, stderr: stderr)
        }
    }

    private func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached { (try? handle.readToEnd()) ?? Data() }.value
    }

    private func waitForExit(_ process: Process) async {
        await Task.detached { process.waitUntilExit() }.value
    }
}
