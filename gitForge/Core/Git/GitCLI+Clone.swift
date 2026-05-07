import Foundation
import os

/// A single tick emitted by `git clone --progress`. `percent` is 0...1 for the
/// current stage; the stage label changes as git moves through "Counting
/// objects", "Receiving objects", "Resolving deltas", etc.
struct CloneProgress: Sendable {
    let stage: String
    let percent: Double
}

extension GitCLI {
    /// `git clone <url> <destination>`. Doesn't need an existing repo —
    /// runs from `$HOME` so `Process` has a valid cwd. The destination's parent
    /// directory must exist; the leaf is created by git itself.
    ///
    /// `onProgress` is invoked off the main actor for every progress line git
    /// emits on stderr (with `--progress`). Honors task cancellation: if the
    /// surrounding Task is cancelled, the underlying process is terminated and
    /// `CancellationError` is thrown.
    static func clone(url: String,
                      destination: URL,
                      branch: String? = nil,
                      onProgress: (@Sendable (CloneProgress) -> Void)? = nil) async throws {
        var args: [String] = ["clone", "--progress"]
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

        // Process supports `terminate()` from any thread, so capturing it for
        // the cancel handler is safe.
        nonisolated(unsafe) let processRef = process

        try await withTaskCancellationHandler {
            async let stdoutData: Data = readToEnd(stdoutPipe.fileHandleForReading)
            async let stderrText: String = readProgress(stderrPipe.fileHandleForReading, onProgress: onProgress)
            async let exitWait: Void = waitForExit(process)

            _ = await stdoutData
            let stderr = await stderrText
            _ = await exitWait

            if process.terminationStatus != 0 {
                // SIGTERM (15) when we cancelled; surface as CancellationError
                // so the caller can distinguish user-cancel from real failures.
                if process.terminationReason == .uncaughtSignal {
                    throw CancellationError()
                }
                logger.error("✗ git \(argsString, privacy: .public) exited \(process.terminationStatus): \(stderr, privacy: .public)")
                throw GitError.commandFailed(args: args, exitCode: process.terminationStatus, stderr: stderr)
            }
        } onCancel: {
            processRef.terminate()
        }
    }

    /// Drains `handle` to EOF, splitting on `\r` (in-place line redraws git
    /// uses for progress) and `\n`, parsing each segment for `Stage: NN%` and
    /// pushing those through `onProgress`. Returns the full text for error
    /// reporting.
    private static func readProgress(_ handle: FileHandle,
                                     onProgress: (@Sendable (CloneProgress) -> Void)?) async -> String {
        await Task.detached {
            var full = ""
            var buffer = ""
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                guard let chunk = String(data: data, encoding: .utf8) else { continue }
                full += chunk
                buffer += chunk
                while let split = buffer.firstIndex(where: { $0 == "\r" || $0 == "\n" }) {
                    let line = String(buffer[..<split])
                    buffer = String(buffer[buffer.index(after: split)...])
                    if let progress = parseProgress(line) {
                        onProgress?(progress)
                    }
                }
            }
            return full
        }.value
    }

    /// Parses a single stderr segment like `"Receiving objects:  47% (123/261)"`
    /// or `"Resolving deltas: 100% (456/456), done."` into a `CloneProgress`.
    private static func parseProgress(_ line: String) -> CloneProgress? {
        // Find ":" — stage label is everything before, then a digit run + "%".
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let stage = line[..<colonIdx].trimmingCharacters(in: .whitespaces)
        guard !stage.isEmpty else { return nil }
        let rest = line[line.index(after: colonIdx)...]
        // Match the first run of digits followed by "%".
        var digits = ""
        var sawPercent = false
        for ch in rest {
            if ch.isNumber {
                digits.append(ch)
            } else if ch == "%", !digits.isEmpty {
                sawPercent = true
                break
            } else if !digits.isEmpty {
                break
            }
        }
        guard sawPercent, let value = Double(digits) else { return nil }
        return CloneProgress(stage: stage, percent: min(max(value / 100, 0), 1))
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached { (try? handle.readToEnd()) ?? Data() }.value
    }

    private static func waitForExit(_ process: Process) async {
        await Task.detached { process.waitUntilExit() }.value
    }
}
