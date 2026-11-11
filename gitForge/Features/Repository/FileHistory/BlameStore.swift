import Foundation
import Observation

/// Blame of one file: its lines at a revision (or in the working tree),
/// filled in with who last changed each as `git blame` streams in, and
/// "Blame before this commit" walking back one commit at a time.
@Observable
@MainActor
final class BlameStore {
    /// What is blamed: the file at a revision, or in the working tree
    /// (`revision` nil), and the line to bring into view.
    struct Location: Equatable, Sendable {
        var revision: String?
        var path: String
        var line: Int? = nil
    }

    enum Phase: Equatable {
        case loading
        case loaded
        case binary
        case tooLarge
        case failed(String)
    }

    private(set) var location: Location
    private(set) var phase: Phase = .loading
    /// The file's lines; row `i` is line `i + 1`.
    private(set) var lines: [String] = []
    /// The index in `ranges` that blames each line, or -1 while git hasn't
    /// got to it.
    private(set) var lineRanges: [Int] = []
    private(set) var ranges: [BlameRange] = []
    private(set) var commits: [String: BlameCommit] = [:]
    /// Lines git has blamed so far.
    private(set) var blamedLineCount = 0
    /// `git blame` is still running.
    private(set) var isBlaming = false
    /// Where each "Blame before this commit" came from, newest last.
    private(set) var backStack: [Location] = []
    /// The line the view keeps in view and marks, and a counter bumped each
    /// time it should scroll there again.
    private(set) var focusLine: Int?
    private(set) var focusSerial = 0
    /// The line the user clicked; the actions above the blame act on it.
    var selectedLine: Int?

    /// Bumped by every load; a stream that's been replaced stops applying.
    private var loadGen: UInt64 = 0
    /// The load the view started last (`run`), cancelled by the next one
    /// and by `stop()`: cancelling it stops git.
    @ObservationIgnored private var running: Task<Void, Never>?
    private let cli: GitCLI
    /// `-w`, read on every load. A test seam.
    @ObservationIgnored var ignoresWhitespace: () -> Bool = { GitPreferences.diffIgnoreWhitespace }

    init(cli: GitCLI, location: Location) {
        self.cli = cli
        self.location = location
    }

    // MARK: Lines

    /// Whether `line` (1-based) has been blamed.
    func range(at line: Int) -> BlameRange? {
        guard lineRanges.indices.contains(line - 1) else { return nil }
        let index = lineRanges[line - 1]
        return index >= 0 ? ranges[index] : nil
    }

    func commit(at line: Int) -> BlameCommit? {
        range(at: line).flatMap { commits[$0.sha] }
    }

    /// The SHA blamed for `line`, `nil` while pending.
    func sha(at line: Int) -> String? {
        range(at: line)?.sha
    }

    /// `line` starts a run of lines from one commit (a gutter group).
    func startsGroup(_ line: Int) -> Bool {
        guard let sha = sha(at: line) else { return false }
        return line == 1 || sha != self.sha(at: line - 1)
    }

    /// Where "Blame before this commit" goes from `line`: `nil` for a line
    /// still pending or blamed on a boundary (root) commit.
    func origin(before line: Int) -> BlameOrigin? {
        range(at: line)?.previous
    }

    var progress: Double {
        lines.isEmpty ? 0 : Double(blamedLineCount) / Double(lines.count)
    }

    // MARK: Loading

    /// Runs `work` (a load, a step back) as the one load in flight,
    /// cancelling the one before it.
    func run(_ work: @escaping @MainActor () async -> Void) {
        running?.cancel()
        running = Task { await work() }
    }

    /// Cancels the load in flight (the view went away).
    func stop() {
        running?.cancel()
        running = nil
    }

    /// Blames the current location again (Hide whitespace flipped, or the
    /// file changed), keeping the selected line in view.
    func reload() async {
        var again = location
        again.line = selectedLine ?? location.line
        await load(again, recordingBack: false)
    }

    /// Reads the file at `location`, then streams its blame in. Returns
    /// when git is done or another load replaced this one.
    func load(_ location: Location, recordingBack: Bool = false) async {
        if recordingBack { backStack.append(currentLocation) }
        loadGen &+= 1
        let gen = loadGen
        self.location = location
        phase = .loading
        lines = []
        lineRanges = []
        ranges = []
        commits = [:]
        blamedLineCount = 0
        selectedLine = location.line
        focusLine = location.line
        isBlaming = true
        defer { if gen == loadGen { isBlaming = false } }

        let source: BlameSource
        do {
            source = try await cli.blameSource(path: location.path, revision: location.revision)
        } catch is CancellationError {
            return
        } catch {
            guard gen == loadGen else { return }
            phase = .failed(Self.message(for: error, location: location))
            return
        }
        guard gen == loadGen else { return }
        switch source {
        case .binary:
            phase = .binary
            return
        case .tooLarge:
            phase = .tooLarge
            return
        case .text(let text):
            lines = text
            lineRanges = Array(repeating: -1, count: text.count)
            phase = .loaded
            focusSerial &+= 1
        }

        do {
            for try await batch in cli.blame(path: location.path, revision: location.revision,
                                             ignoreWhitespace: ignoresWhitespace()) {
                // Leaving the loop cancels the stream, which stops git.
                guard gen == loadGen else { return }
                apply(batch)
            }
        } catch is CancellationError {
            return
        } catch {
            guard gen == loadGen else { return }
            phase = .failed(Self.message(for: error, location: location))
        }
    }

    private func apply(_ batch: BlameParser.Batch) {
        for commit in batch.commits where commits[commit.sha] == nil {
            commits[commit.sha] = commit
        }
        guard !batch.ranges.isEmpty else { return }
        var owners = lineRanges
        var all = ranges
        var blamed = blamedLineCount
        for range in batch.ranges {
            let index = all.count
            all.append(range)
            let first = max(range.finalLine - 1, 0)
            let end = min(range.finalLine - 1 + range.count, owners.count)
            guard first < end else { continue }
            for row in first..<end where owners[row] < 0 {
                owners[row] = index
                blamed += 1
            }
        }
        ranges = all
        lineRanges = owners
        blamedLineCount = blamed
    }

    /// Where the view is: the location with the selected line.
    private var currentLocation: Location {
        var here = location
        here.line = selectedLine ?? location.line
        return here
    }

    // MARK: Walking back

    /// Blames the parent revision `line` came from, keeping that line in
    /// view: what it looked like before the commit that last changed it.
    /// Does nothing for a line without one (pending, or a boundary commit).
    func blameBefore(line: Int) async {
        guard let range = range(at: line), let origin = range.previous else { return }
        let target = await cli.lineBefore(range.sourceLine(for: line), path: range.path, at: range.sha,
                                          parent: origin.sha, parentPath: origin.path)
        guard !Task.isCancelled else { return }
        selectedLine = line
        await load(Location(revision: origin.sha, path: origin.path, line: target), recordingBack: true)
    }

    /// Back to where the last "Blame before this commit" started.
    func goBack() async {
        guard let previous = backStack.popLast() else { return }
        await load(previous, recordingBack: false)
    }

    /// git's "no such path 'x' in HEAD" as words.
    private static func message(for error: Error, location: Location) -> String {
        if case GitError.commandFailed(_, _, let stderr) = error, stderr.contains("no such path") {
            return location.revision == nil
                ? String(localized: "This file isn’t committed yet, so there is nothing to blame.")
                : String(localized: "The file isn’t there at this revision.")
        }
        if (error as NSError).domain == NSCocoaErrorDomain {
            return String(localized: "The file isn’t in the working tree. Blame it at a commit from its history.")
        }
        return error.userMessage
    }
}
