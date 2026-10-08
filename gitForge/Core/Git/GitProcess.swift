import Foundation
import os

/// Single place that knows how to spawn `git`. `GitCLI.run`, `GitCLI.clone`
/// and `GitGlobalConfigReader` all build their `Process` here so the global
/// flags and the non-interactive environment can't drift between them.
nonisolated enum GitProcess {
    /// Builds a configured, not-yet-launched `git` process.
    ///
    /// Global flags applied to every invocation:
    ///   • `-c core.quotePath=false`: emit paths verbatim instead of the
    ///     C-escaped `"caf\303\251.txt"` form. Without this the porcelain
    ///     parser keeps the literal escapes and a subsequent `git add --`
    ///     fails because the pathspec doesn't match any file on disk.
    ///   • `-c core.precomposeUnicode=true`: macOS git default is already
    ///     true, but forcing it shields users who set it to false in their
    ///     global config (NFD-vs-NFC mismatches break Swift `String == String`
    ///     comparisons in the VM).
    ///
    /// NOTE: `--no-optional-locks` was here too in an earlier pass to avoid
    /// two reads colliding on `.git/index`. It also prevents `git status`
    /// from refreshing the index, which surfaces as false-positive `M`
    /// entries when an editor rewrites a file with the same content (mtime
    /// changes, content doesn't). Removed — the watcher's own serialisation
    /// (isMutating + suspend / debounce) already covers the collision case.
    static func make(arguments: [String],
                     workingDirectory: URL,
                     executablePath: String = "/usr/bin/env") -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = [
            "git",
            "-c", "core.quotePath=false",
            "-c", "core.precomposeUnicode=true",
        ] + arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment()
        return process
    }

    /// Guards that keep git from hanging on input we can't provide:
    ///   • GIT_TERMINAL_PROMPT=0 — no stdin prompt for HTTPS credentials.
    ///   • GIT_ASKPASS=/usr/bin/true — overrides any GUI askpass that
    ///     `core.askPass` config or other tooling (GitHub CLI, third-party
    ///     helpers) might have set. Without this, a configured askpass can
    ///     pop a hidden dialog and block forever waiting on it. `true`
    ///     returns an empty string; git treats it as "no credentials" and
    ///     either uses what `credential.helper` provided or fails fast.
    ///   • GIT_SSH_COMMAND with BatchMode=yes — ssh refuses to prompt for a
    ///     passphrase when the key isn't unlocked in the agent / Keychain.
    ///   • GIT_EDITOR=/usr/bin/true — keeps merge/pull-merge/rebase from
    ///     trying to open vi for a commit message; defaults are accepted.
    /// Credential helpers (osxkeychain, GitHub CLI's gh-credential…) still
    /// run first via `credential.helper`; these vars only suppress the
    /// fallbacks that would otherwise block on a TTY or GUI we can't drive.
    ///
    /// `LC_ALL=C` pins git's output language so `RemoteFailure(stderr:)`
    /// (which matches English substrings) categorises reliably. Otherwise a
    /// user with LANG=es_ES sees `.other` + raw stderr.
    static func environment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GIT_ASKPASS"] = "/usr/bin/true"
        if environment["GIT_SSH_COMMAND"] == nil {
            environment["GIT_SSH_COMMAND"] = "ssh -o BatchMode=yes"
        }
        environment["GIT_EDITOR"] = "/usr/bin/true"
        environment["LC_ALL"] = "C"
        return environment
    }

    /// Lossy UTF-8 decode. git emits file *contents* verbatim in diffs, so a
    /// single Latin-1 / Windows-1252 byte made the strict
    /// `String(data:encoding:)` return nil and the whole output collapse to
    /// "" — the diff pane then claimed there were no changes. Invalid bytes
    /// become U+FFFD instead; everything else survives intact.
    static func decode(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    /// Launches `process` and returns a handle to await its exit.
    ///
    /// Never `waitUntilExit()` from async code: it spins the *calling*
    /// thread's run loop, and when that isn't the thread that launched the
    /// process (an actor hop or a detached task away) the exit can go
    /// unnoticed forever — a cooperative thread stays blocked on a process
    /// that is long gone. `terminationHandler` is delivered by Foundation on
    /// its own queue, so it's installed before launch and bridged to a
    /// continuation instead.
    static func start(_ process: Process) throws -> ProcessExit {
        let exit = ProcessExit()
        process.terminationHandler = { _ in exit.signal() }
        do {
            try process.run()
        } catch {
            process.terminationHandler = nil
            throw error
        }
        return exit
    }

    /// Runs a non-git helper tool to completion. Returns its exit status, or
    /// nil if it couldn't be launched.
    static func runTool(_ executable: String, arguments: [String]) async -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard let exit = try? start(process) else { return nil }
        await exit.wait()
        return process.terminationStatus
    }

    /// Reads `handle` to EOF on a GCD thread. Blocking reads must stay off
    /// Swift's cooperative pool: it has one thread per core, and a refresh
    /// fires several git commands at once, each holding two readers.
    static func readToEnd(_ handle: FileHandle) async -> Data {
        await offPool { (try? handle.readToEnd()) ?? Data() }
    }

    /// Runs blocking `work` on a global GCD queue (which grows threads as
    /// needed) and resumes with its result.
    static func offPool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}

/// One-shot exit signal for a launched `Process`. `signal()` may run before
/// or after `wait()` starts; either order resumes exactly once.
nonisolated final class ProcessExit: @unchecked Sendable {
    private let lock = NSLock()
    private var exited = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func signal() {
        lock.lock()
        exited = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if exited {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }
}

/// Progress-based watchdog for a running git subprocess. Callers `tick()`
/// whenever output flows; if nothing arrives for `timeout` seconds the
/// process is terminated (SIGTERM, then SIGKILL). A large push or clone that
/// keeps reporting progress runs uninterrupted, while a DNS hang or askpass
/// deadlock dies quickly because nothing flows.
///
/// `timedOut` lets callers tell a watchdog kill apart from a user
/// cancellation — both end with `terminationReason == .uncaughtSignal`.
nonisolated final class GitWatchdog: @unchecked Sendable {
    let timeout: TimeInterval
    private let pollInterval: Duration
    private let lock = NSLock()
    private var lastProgressAt = Date()
    private var didTimeOut = false
    private var task: Task<Void, Never>?

    init(timeout: TimeInterval, pollInterval: Duration = .seconds(5)) {
        self.timeout = timeout
        self.pollInterval = pollInterval
    }

    /// Resets the idle timer. Called from the detached pipe readers.
    func tick() {
        lock.lock(); defer { lock.unlock() }
        lastProgressAt = Date()
    }

    var timedOut: Bool {
        lock.lock(); defer { lock.unlock() }
        return didTimeOut
    }

    /// The message surfaced when the watchdog killed a command that printed
    /// nothing useful. Phrased so `RemoteFailure(stderr:)` routes it to
    /// `.network`.
    var timeoutMessage: String {
        "connection timed out after \(Int(timeout))s — the remote may be unreachable, or git is stuck on something the app can't drive non-interactively."
    }

    func start(watching process: Process, label: String, logger: Logger) {
        let timeout = timeout
        let pollInterval = pollInterval
        let newTask = Task { [weak self] in
            while !Task.isCancelled, process.isRunning {
                try? await Task.sleep(for: pollInterval)
                guard let self, self.idleTime() > timeout else { continue }
                self.markTimedOut()
                logger.error("watchdog: terminating `git \(label, privacy: .public)` after \(timeout, privacy: .public)s without progress")
                process.terminate()
                try? await Task.sleep(for: .milliseconds(500))
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                break
            }
        }
        lock.lock(); task = newTask; lock.unlock()
    }

    func stop() {
        lock.lock(); let current = task; task = nil; lock.unlock()
        current?.cancel()
    }

    private func idleTime() -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return Date().timeIntervalSince(lastProgressAt)
    }

    private func markTimedOut() {
        lock.lock(); defer { lock.unlock() }
        didTimeOut = true
    }
}
