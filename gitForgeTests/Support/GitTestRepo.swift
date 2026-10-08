import Foundation
@testable import gitForge

/// Throwaway on-disk repository for tests that need real `git` behaviour.
/// Setup commands run with the user's global and system config disabled so
/// a personal `commit.gpgsign` or hook can't make fixtures flaky. `GitCLI`
/// itself still runs with the normal environment — that's what's under test.
struct GitTestRepo {
    struct CommandFailed: Error, CustomStringConvertible {
        let args: [String]
        let output: String
        var description: String { "git \(args.joined(separator: " ")) failed: \(output)" }
    }

    let url: URL

    var cli: GitCLI { GitCLI(workingDirectory: url) }

    init(bare: Bool = false) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if bare {
            try git("init", "-q", "--bare", "-b", "main")
        } else {
            try git("init", "-q", "-b", "main")
            try git("config", "user.name", "Test")
            try git("config", "user.email", "test@example.com")
            try git("config", "commit.gpgsign", "false")
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func git(_ args: String...) throws -> String {
        try git(args)
    }

    @discardableResult
    func git(_ args: [String], allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git"] + args
        process.currentDirectoryURL = url
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["LC_ALL"] = "C"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        // Not `waitUntilExit()`: from a Swift Testing (cooperative) thread it
        // can miss the exit and hang. See `GitProcess.start`.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        let output = String(decoding: data, as: UTF8.self)
        if process.terminationStatus != 0, !allowFailure {
            throw CommandFailed(args: args, output: output)
        }
        return output
    }

    func write(_ text: String, to path: String) throws {
        try write(Data(text.utf8), to: path)
    }

    func write(_ data: Data, to path: String) throws {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: file)
    }

    func read(_ path: String) -> String? {
        try? String(contentsOf: url.appendingPathComponent(path), encoding: .utf8)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(path).path(percentEncoded: false))
    }

    /// Writes `files`, stages everything and commits. Returns the new SHA.
    @discardableResult
    func commit(_ message: String, files: [String: String] = [:]) throws -> String {
        for (path, text) in files { try write(text, to: path) }
        try git("add", "-A")
        try git("commit", "-q", "--allow-empty", "-m", message)
        return try git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `git status --porcelain` lines, sorted, for compact assertions.
    func porcelain() throws -> [String] {
        try git("status", "--porcelain").split(separator: "\n").map(String.init).sorted()
    }
}
