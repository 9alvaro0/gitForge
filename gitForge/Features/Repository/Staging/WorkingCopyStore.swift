import Foundation
import Observation

/// The working copy: `git status`, the files ticked for a batch stage, the
/// file open in the diff pane and its diff, and the commit composer's text.
/// Owned by `RepositoryViewModel` (`viewModel.workingCopy`). The mutating
/// operations (stage / unstage / discard / commit) stay on the view model —
/// they take `isMutating` and refresh the whole session.
@Observable
@MainActor
final class WorkingCopyStore {
    // MARK: Status
    var status: WorkingCopyStatus = WorkingCopyStatus(files: []) {
        didSet {
            guard oldValue.isClean != status.isClean else { return }
            onCleanChange?()
        }
    }
    /// Called when the working tree turns dirty or clean (`status.isClean` flips), not on
    /// every status read. The view model lays the history graph out again. Not called by
    /// `purge()`.
    @ObservationIgnored var onCleanChange: (() -> Void)?
    /// `+N −M` per path for the Staged rows (index vs HEAD) and the Unstaged
    /// rows (worktree vs index). Untracked and binary files have none.
    var stagedLineCounts: [String: DiffStats] = [:]
    var unstagedLineCounts: [String: DiffStats] = [:]
    /// Paths the user ticked in the Changes column for a batch stage/unstage.
    /// Separate from `selectedWorkingCopyFile` (which drives the diff pane)
    /// so the user can keep one file visible in the diff while ticking a
    /// disjoint set for staging.
    var selectedFilePaths: Set<String> = []
    /// Anchor and current run of ⌘ / Shift ticking. Not drawn, so not observed.
    @ObservationIgnored var ticking = StagingTicking()
    var isLoadingStatus = false
    /// Distinguishes "never loaded" from "loaded and clean" so the Changes
    /// view doesn't briefly flash "Working tree is clean" on first paint.
    var hasLoadedStatusOnce = false
    /// Bumped at the start of every `refreshStatus()` call. The status
    /// loader is the highest-traffic refresh in the session (watcher, every
    /// stage/unstage/discard, every integration op, manual refresh, …)
    /// so two overlapping calls are common; the post-await guard keeps
    /// the older one from stomping fresh `status` and from flipping the
    /// spinner off while the fresher call is still mid-flight.
    var statusGen: UInt64 = 0

    // MARK: Composer
    var commitSubject: String = ""
    var commitBody: String = ""
    var amendMode: Bool = false {
        didSet {
            guard oldValue != amendMode else { return }
            if amendMode {
                tasks.track { [weak self] in await self?.prefillFromHead() }
            } else {
                commitSubject = ""
                commitBody = ""
            }
        }
    }

    /// Adds `Signed-off-by:` to commits. Remembered per repository: it's a
    /// project's rule (DCO), not a personal habit.
    var signOff: Bool {
        didSet {
            guard oldValue != signOff else { return }
            defaults.set(signOff, forKey: signOffKey)
        }
    }

    // MARK: Diff
    /// Which part of the selected file the pane shows — it matters for a
    /// file with both staged and unstaged changes. Set by `select(_:side:)`
    /// from the Staged / Unstaged lists; `nil` shows the staged part when
    /// there is one (History's uncommitted view).
    private(set) var selectedSide: WorkingCopySide?

    var selectedWorkingCopyFile: WorkingCopyFile? {
        didSet {
            guard oldValue != selectedWorkingCopyFile else { return }
            workingCopyDiffGen &+= 1
            if let file = selectedWorkingCopyFile {
                tasks.track { [weak self] in await self?.loadWorkingCopyDiff(file: file) }
            } else {
                workingCopyDiff = []
                workingCopyDiffEmptyState = .empty
                loadingWorkingCopyDiff = false
            }
        }
    }
    var workingCopyDiff: [DiffHunk] = []
    /// Why the diff is empty (binary, rename-only, …).
    var workingCopyDiffEmptyState: DiffEmptyState = .empty
    var loadingWorkingCopyDiff = false
    /// Selection-change token for the diff pane; loaders drop their
    /// write-back if it moves while they're awaiting.
    var workingCopyDiffGen: UInt64 = 0

    /// Hard ceiling on bytes read from disk when synthesizing an untracked
    /// file's diff. Anything larger gets a "binary"-style placeholder so we
    /// don't blow up trying to render a 50 MB log as a single hunk.
    private static let untrackedDiffByteCap = 1_000_000

    // MARK: Dependencies
    private let cli: GitCLI
    private let repositoryURL: URL
    private let tasks: OwnedTasks
    private let defaults: UserDefaults

    init(cli: GitCLI, repositoryURL: URL, tasks: OwnedTasks, defaults: UserDefaults = .standard) {
        self.cli = cli
        self.repositoryURL = repositoryURL
        self.tasks = tasks
        self.defaults = defaults
        signOff = defaults.bool(forKey: Self.signOffKey(for: repositoryURL))
    }

    private var signOffKey: String { Self.signOffKey(for: repositoryURL) }

    static func signOffKey(for repositoryURL: URL) -> String {
        "gitForge.signOff.\(repositoryURL.standardizedFileURL.path(percentEncoded: false))"
    }

    /// Drops the status and diff when the session stops. Without calling `onCleanChange`:
    /// the session's tasks are already cancelled, and a graph laid out again now would be
    /// tracked after that (`HistoryStore.purge()` hides the Uncommitted changes row itself).
    func purge() {
        let onCleanChange = onCleanChange
        self.onCleanChange = nil
        defer { self.onCleanChange = onCleanChange }
        status = WorkingCopyStatus(files: [])
        stagedLineCounts = [:]
        unstagedLineCounts = [:]
        selectedFilePaths = []
        ticking = StagingTicking()
        workingCopyDiff = []
    }

    // MARK: Status

    /// Reads `git status` and applies the result. Gen-token gated because
    /// this is the highest-traffic refresh in the session — overlapping calls
    /// would otherwise flicker the spinner off mid-flight (older `defer`
    /// firing while a fresher call is still awaiting) and leak stale
    /// `status` / selection-prune writes.
    func refreshStatus() async {
        statusGen &+= 1
        let gen = statusGen
        isLoadingStatus = true
        defer {
            if gen == statusGen {
                isLoadingStatus = false
                hasLoadedStatusOnce = true
            }
        }
        do {
            // The counts are decoration: a failure leaves them empty rather
            // than failing the refresh.
            async let staged = try? cli.lineCounts(staged: true)
            async let unstaged = try? cli.lineCounts(staged: false)
            let snapshot = try await cli.status()
            let (stagedCounts, unstagedCounts) = await (staged, unstaged)
            guard gen == statusGen else { return }
            status = snapshot
            stagedLineCounts = stagedCounts ?? [:]
            unstagedLineCounts = unstagedCounts ?? [:]
            // Keep the diff-pane selection current: drop it when the file
            // left the status set (discarded, deleted), and swap in the fresh
            // entry when its state moved (a hunk staged, so it's now also
            // staged) — the swap reloads the diff.
            if let selected = selectedWorkingCopyFile {
                let fresh = status.files.first { $0.path == selected.path }
                if fresh != selected { selectedWorkingCopyFile = fresh }
            }
        } catch {
            // Underlying `git status` failure is already logged by GitCLI.
        }
    }

    /// Opens `file` in the diff pane on `side`. Picking the other side of the
    /// file that's already open reloads the diff, since the file itself
    /// didn't change.
    func select(_ file: WorkingCopyFile?, side: WorkingCopySide?) {
        let sideChanged = side != selectedSide
        selectedSide = side
        if let file, file == selectedWorkingCopyFile {
            guard sideChanged else { return }
            workingCopyDiffGen &+= 1
            tasks.track { [weak self] in await self?.loadWorkingCopyDiff(file: file) }
        } else {
            selectedWorkingCopyFile = file
        }
    }

    /// The side the pane shows for `file`: the requested one while the file
    /// still has changes there, otherwise whichever it has.
    func diffSide(for file: WorkingCopyFile) -> WorkingCopySide {
        switch selectedSide {
        case .staged where file.isStaged: .staged
        case .unstaged where file.isUnstaged: .unstaged
        default: file.isStaged ? .staged : .unstaged
        }
    }

    /// Reloads the diff of the file open in the pane, so an external edit or
    /// discard repaints it. Skipped when the file has left the status set —
    /// `refreshStatus` prunes that selection itself.
    func reloadSelectedDiff() async {
        guard let selected = selectedWorkingCopyFile,
              status.files.contains(where: { $0.path == selected.path }) else { return }
        await loadWorkingCopyDiff(file: selected)
    }

    /// The new side of `file`'s open diff — the index for the staged part,
    /// the file on disk for the unstaged one — for "Show N hidden lines".
    func newSideLines(for file: WorkingCopyFile) async -> [String]? {
        if diffSide(for: file) == .staged {
            return await cli.fileLines(revision: "", path: file.path)
        }
        let url = repositoryURL.appendingPathComponent(file.path)
        return await Task.detached {
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  data.count <= DiffGaps.maxFileBytes else { return nil }
            return DiffGaps.splitLines(GitProcess.decode(data))
        }.value
    }

    // MARK: Bulk selection

    /// Toggle a single file's membership in the batch-selection set.
    func toggleSelection(_ file: WorkingCopyFile) {
        ticking.forgetRun()
        if selectedFilePaths.contains(file.path) {
            selectedFilePaths.remove(file.path)
        } else {
            selectedFilePaths.insert(file.path)
        }
    }

    /// Tick or untick a whole section at once (the select-all checkbox).
    func setSelection(_ files: [WorkingCopyFile], selected: Bool) {
        ticking.forgetRun()
        if selected {
            selectedFilePaths.formUnion(files.map(\.path))
        } else {
            deselect(files)
        }
    }

    /// Drop every selection that comes from `files`. Used after a batch
    /// stage/unstage so the ticks don't reappear on a fresh section the rows
    /// just moved into.
    func deselect(_ files: [WorkingCopyFile]) {
        ticking.forgetRun()
        for f in files { selectedFilePaths.remove(f.path) }
    }

    /// Selected files with unstaged changes, including partially staged ones
    /// (they're listed under Unstaged too).
    var selectedUnstagedFiles: [WorkingCopyFile] {
        status.files.filter { selectedFilePaths.contains($0.path) && $0.isUnstaged }
    }

    /// Selected files that are currently staged.
    var selectedStagedFiles: [WorkingCopyFile] {
        status.files.filter { selectedFilePaths.contains($0.path) && $0.isStaged }
    }

    // MARK: Composer

    /// Empties the composer after a successful commit.
    func resetComposer() {
        commitSubject = ""
        commitBody = ""
        amendMode = false
    }

    func prefillFromHead() async {
        do {
            let result = try await cli.run(["log", "-1", "HEAD", "--format=%B"])
            // A `false → true → false` toggle on `amendMode` clears
            // subject/body via the off-branch of the didSet. If this
            // prefill resumes after that, writing HEAD's message back
            // would look like the user re-armed amend. Bail when the
            // toggle has flipped off underneath us.
            guard amendMode else { return }
            let message = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let firstNewline = message.firstIndex(of: "\n") {
                commitSubject = String(message[..<firstNewline])
                commitBody = String(message[message.index(after: firstNewline)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                commitSubject = message
                commitBody = ""
            }
        } catch {
            // Underlying `git log` failure is already logged by GitCLI.
        }
    }

    // MARK: Diff

    func loadWorkingCopyDiff(file: WorkingCopyFile) async {
        let gen = workingCopyDiffGen
        loadingWorkingCopyDiff = true
        defer {
            if gen == workingCopyDiffGen { loadingWorkingCopyDiff = false }
        }
        do {
            let side = diffSide(for: file)
            if file.isUntracked && side == .unstaged {
                let synthesized = await synthesizeUntrackedDiff(path: file.path)
                guard gen == workingCopyDiffGen else { return }
                workingCopyDiff = DiffParser.parse(synthesized.raw)
                workingCopyDiffEmptyState = workingCopyDiff.isEmpty ? synthesized.emptyState : .empty
                return
            }
            let raw: String
            if file.isUnmerged {
                raw = try await cli.diffAgainstHead(file: file.path)
            } else if side == .staged {
                raw = try await cli.diffStaged(file: file.path, originalPath: file.originalPath)
            } else {
                raw = try await cli.diffUnstaged(file: file.path)
            }
            guard gen == workingCopyDiffGen else { return }
            let hunks = DiffParser.parse(raw)
            workingCopyDiff = hunks
            workingCopyDiffEmptyState = hunks.isEmpty ? DiffEmptyState.classifying(raw: raw, ignoringWhitespace: GitPreferences.diffIgnoreWhitespace) : .empty
        } catch {
            guard gen == workingCopyDiffGen else { return }
            workingCopyDiff = []
            workingCopyDiffEmptyState = .empty
        }
    }

    /// Reads an untracked file off the main thread and emits a unified-diff
    /// string that marks every line as added. Empty files and binaries
    /// short-circuit to an empty raw string + the matching `DiffEmptyState`
    /// so the renderer can show a meaningful placeholder.
    ///
    /// Binary detection mirrors git's heuristic: a NUL byte in the first 8 KB
    /// of the file is enough to classify as binary. Files larger than
    /// `untrackedDiffByteCap` are also routed through the binary path — the
    /// goal is "tell the user something exists", not "parse a 50 MB log".
    private func synthesizeUntrackedDiff(path: String) async -> (raw: String, emptyState: DiffEmptyState) {
        let absolute = repositoryURL.appendingPathComponent(path)
        let cap = Self.untrackedDiffByteCap
        return await Task.detached {
            guard let data = try? Data(contentsOf: absolute, options: [.mappedIfSafe]) else {
                return ("", DiffEmptyState.empty)
            }
            if data.isEmpty {
                return ("", DiffEmptyState.empty)
            }
            if data.count > cap {
                return ("", DiffEmptyState.untrackedBinary)
            }
            let probeLength = min(8000, data.count)
            if data.prefix(probeLength).contains(0) {
                return ("", DiffEmptyState.untrackedBinary)
            }
            // Lossy, like every other diff path (see `GitProcess.decode`):
            // a Latin-1 text file is still text, not "binary".
            return (Self.synthesizeAddDiff(text: GitProcess.decode(data)), DiffEmptyState.empty)
        }.value
    }

    /// Builds a single `@@ -0,0 +1,N @@` hunk where every line is a `+`. The
    /// `\ No newline at end of file` trailer matches what `git diff` emits so
    /// the parser's existing newline handling kicks in unchanged.
    nonisolated static func synthesizeAddDiff(text: String) -> String {
        guard !text.isEmpty else { return "" }
        let endsWithNewline = text.hasSuffix("\n")
        let lines = text.components(separatedBy: "\n")
        // `components(separatedBy:)` leaves a trailing empty element when the
        // string ends with a newline — that element isn't a real line, drop it.
        let actual: ArraySlice<String> = endsWithNewline ? lines.dropLast() : ArraySlice(lines)
        guard !actual.isEmpty else { return "" }
        var output = "@@ -0,0 +1,\(actual.count) @@\n"
        output += actual.map { "+\($0)" }.joined(separator: "\n")
        output += "\n"
        if !endsWithNewline {
            output += "\\ No newline at end of file\n"
        }
        return output
    }
}

/// The two parts of a working-copy file: its staged changes (index vs HEAD)
/// and its unstaged ones (worktree vs index).
nonisolated enum WorkingCopySide: Sendable, Hashable {
    case staged, unstaged
}
