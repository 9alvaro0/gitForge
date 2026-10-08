import Foundation
import os

/// A single tick emitted by `git clone --progress`. `percent` is 0...1 for the
/// current stage; the stage label changes as git moves through "Counting
/// objects", "Receiving objects", "Resolving deltas", etc.
struct CloneProgress: Sendable {
    let stage: String
    let percent: Double
}

/// Whitelist for clone URLs. Accepting raw strings here is the path that lets
/// a malicious repo URL like `--upload-pack=evil` reach git as a flag (the
/// CVE-2017-1000117 family). We reject the dash prefix outright and require
/// one of the network schemes git is normally driven with — local paths and
/// `file://` are intentionally out for now; if a user needs them, surface a
/// dedicated affordance instead of widening this gate.
enum CloneURLValidator {
    enum Failure: Error, LocalizedError, Equatable {
        case empty
        case startsWithDash
        case unsupportedScheme(String)

        var errorDescription: String? {
            switch self {
            case .empty:
                "Clone URL is empty."
            case .startsWithDash:
                "Clone URL can't start with '-' — git would treat it as an option."
            case .unsupportedScheme(let raw):
                "Unsupported clone URL: \(raw). Use https://, http://, ssh://, git://, or git@host:path."
            }
        }
    }

    /// Returns the trimmed URL on success.
    @discardableResult
    nonisolated static func validate(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        guard !trimmed.hasPrefix("-") else { throw Failure.startsWithDash }
        let lower = trimmed.lowercased()
        let allowedSchemes = ["https://", "http://", "ssh://", "git://"]
        if allowedSchemes.contains(where: { lower.hasPrefix($0) }) { return trimmed }
        // SCP-like: `user@host:path`. Require `@` strictly before the first `:`
        // and a non-empty user segment so a stray `:` in some other shape can't
        // pass.
        if let atIndex = trimmed.firstIndex(of: "@"),
           let colonIndex = trimmed.firstIndex(of: ":"),
           atIndex < colonIndex,
           atIndex != trimmed.startIndex {
            return trimmed
        }
        throw Failure.unsupportedScheme(trimmed)
    }
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
        let safeURL = try CloneURLValidator.validate(url)
        let safeBranch: String? = try {
            guard let branch else { return nil }
            let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            // `--branch` consumes the next argv as its value; without this guard,
            // a name starting with `-` would be re-parsed by git as a flag.
            guard !trimmed.hasPrefix("-") else {
                throw GitError.launchFailed("Branch name can't start with '-'.")
            }
            return trimmed
        }()
        var args: [String] = ["clone", "--progress"]
        if let safeBranch { args += ["--branch", safeBranch] }
        args.append(endOfOptions)
        args += [safeURL, destination.path(percentEncoded: false)]

        let parent = destination.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: parent.path(percentEncoded: false)) {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        }

        // Clone runs from `$HOME` so `Process` has a valid cwd; the
        // destination is passed explicitly in argv.
        let process = GitProcess.make(arguments: args,
                                      workingDirectory: URL(fileURLWithPath: NSHomeDirectory()))
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let argsString = redacted(args.joined(separator: " "))
        logger.info("→ git \(argsString, privacy: .public)")

        let exit: ProcessExit
        do {
            exit = try GitProcess.start(process)
        } catch {
            throw GitError.launchFailed(error.localizedDescription)
        }

        // Resets on every stage tick git emits. A stuck clone (DNS hung,
        // askpass deadlock, BatchMode rejected) is terminated; large clones
        // run uninterrupted as long as they keep reporting bytes.
        let watchdog = GitWatchdog(timeout: TimeInterval(GitPreferences.gitTimeoutSeconds))
        let tickedProgress: @Sendable (CloneProgress) -> Void = { p in
            watchdog.tick()
            onProgress?(p)
        }
        watchdog.start(watching: process, label: argsString, logger: logger)
        defer { watchdog.stop() }

        try await withTaskCancellationHandler {
            async let stdoutData: Data = GitProcess.readToEnd(stdoutPipe.fileHandleForReading)
            async let stderrText: String = readProgress(stderrPipe.fileHandleForReading,
                                                        onProgress: tickedProgress,
                                                        onActivity: { watchdog.tick() })
            async let exitWait: Void = exit.wait()

            _ = await stdoutData
            let capturedStderr = await stderrText
            _ = await exitWait

            guard process.terminationStatus != 0 else { return }
            if process.terminationReason == .uncaughtSignal {
                // Killed by a signal: either the user cancelled (onCancel
                // below) or the watchdog gave up. Only the former is a
                // CancellationError — a stalled clone must surface as a
                // network failure, not vanish as if the user had cancelled.
                guard watchdog.timedOut else { throw CancellationError() }
                logger.error("✗ git \(argsString, privacy: .public) timed out")
                throw GitError.commandFailed(args: args,
                                             exitCode: process.terminationStatus,
                                             stderr: watchdog.timeoutMessage)
            }
            let redactedStderr = redacted(capturedStderr.trimmingCharacters(in: .whitespacesAndNewlines))
            logger.error("✗ git \(argsString, privacy: .public) exited \(process.terminationStatus): \(redactedStderr, privacy: .public)")
            throw GitError.commandFailed(args: args, exitCode: process.terminationStatus, stderr: capturedStderr)
        } onCancel: {
            // `Process` is Sendable and `terminate()` is safe from any thread.
            process.terminate()
        }
    }

    /// Drains `handle` to EOF, splitting on `\r` (in-place line redraws git
    /// uses for progress) and `\n`, parsing each segment for `Stage: NN%` and
    /// pushing those through `onProgress`. `onActivity` fires for every chunk
    /// so the watchdog sees git is alive even between percentage updates.
    /// Bytes are buffered raw and decoded per complete line, so a multi-byte
    /// character split across two reads isn't mangled. Returns the full text
    /// for error reporting.
    private static func readProgress(_ handle: FileHandle,
                                     onProgress: (@Sendable (CloneProgress) -> Void)?,
                                     onActivity: @escaping @Sendable () -> Void) async -> String {
        await GitProcess.offPool {
            var full = Data()
            var buffer = Data()
            let separators: Set<UInt8> = [0x0D, 0x0A] // \r, \n
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                onActivity()
                full.append(data)
                buffer.append(data)
                while let split = buffer.firstIndex(where: { separators.contains($0) }) {
                    let line = GitProcess.decode(buffer[buffer.startIndex..<split])
                    buffer = Data(buffer[buffer.index(after: split)...])
                    if let progress = parseProgress(line) {
                        onProgress?(progress)
                    }
                }
            }
            return GitProcess.decode(full)
        }
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
}
