import Foundation
import Observation
import os

/// State of the conflict resolver: the unmerged files, the hunks of the
/// selected one and the user's per-hunk picks. Owned by `RepositoryViewModel`
/// (`viewModel.conflicts`).
///
/// The view model keeps `mergeState` (its guards need it everywhere) and the
/// operations that touch the index — resolving, aborting, continuing — which
/// run under `isMutating`.
@Observable
@MainActor
final class ConflictStore {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "conflicts")

    var files: [ConflictFile] = []
    var hunks: [ConflictHunk] = []
    var selectedPath: String?
    var picks: [UUID: ConflictHunk.Pick] = [:]
    /// Bumped by `loadHunks`; a slow read for an older path drops its write
    /// so it can't stomp the freshly selected file.
    var hunksGen: UInt64 = 0

    private let repositoryURL: URL

    init(repositoryURL: URL) {
        self.repositoryURL = repositoryURL
    }

    /// Re-scans `paths` (the unmerged set) and keeps the user's selection
    /// when it's still there, so a watcher tick mid-resolve doesn't yank
    /// them back to the top of the list.
    func reload(unmergedPaths paths: [String]) async {
        files = await Self.scan(paths: paths, repositoryURL: repositoryURL)
        if let selectedPath, files.contains(where: { $0.path == selectedPath }) {
            return
        }
        if let candidate = files.first(where: { !$0.resolved }) ?? files.first {
            await loadHunks(for: candidate.path)
        }
    }

    /// Loads the hunks of `path` and resets pending picks.
    func loadHunks(for path: String) async {
        hunksGen &+= 1
        let gen = hunksGen
        selectedPath = path
        let url = repositoryURL.appendingPathComponent(path)
        do {
            let contents = try await Self.read(url)
            guard gen == hunksGen else { return }
            hunks = ConflictParser.parse(contents.text).hunks
            picks = [:]
        } catch {
            guard gen == hunksGen else { return }
            Self.logger.error("Failed to read \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            hunks = []
            picks = [:]
        }
    }

    func setPick(hunkId: UUID, pick: ConflictHunk.Pick) {
        picks[hunkId] = pick
    }

    /// Clean tree: nothing to resolve.
    func clear() {
        files = []
        hunks = []
        picks = [:]
        selectedPath = nil
    }

    enum ResolveError: LocalizedError {
        case changedOnDisk(path: String)

        var errorDescription: String? {
            switch self {
            case .changedOnDisk(let path):
                "“\(path)” changed on disk — reload conflicts before resolving."
            }
        }
    }

    /// Writes the picks into the selected file, preserving its encoding.
    /// Refuses if the file's hunk count shifted under us: an external edit
    /// landed and the picks no longer line up with the on-disk content.
    /// Returns the path written; the caller stages it.
    func writeResolution() async throws -> String? {
        guard let path = selectedPath else { return nil }
        let url = repositoryURL.appendingPathComponent(path)
        let original = try await Self.read(url)
        guard ConflictParser.parse(original.text).hunks.count == hunks.count else {
            throw ResolveError.changedOnDisk(path: path)
        }
        let resolved = ConflictParser.apply(content: original.text, picks: picks, hunks: hunks)
        try TextFile.write(resolved, encoding: original.encoding, to: url)
        return path
    }

    private nonisolated static func read(_ url: URL) async throws -> TextFile.Contents {
        let result: Result<TextFile.Contents, Error> = await GitProcess.offPool { Result { try TextFile.read(url) } }
        return try result.get()
    }

    /// Reads each conflicted file off the main actor and in parallel — a big
    /// merge can surface dozens of files.
    private nonisolated static func scan(paths: [String], repositoryURL: URL) async -> [ConflictFile] {
        await withTaskGroup(of: (Int, ConflictFile).self) { group in
            for (index, path) in paths.enumerated() {
                group.addTask {
                    let url = repositoryURL.appendingPathComponent(path)
                    let found = (try? TextFile.read(url)).map { ConflictParser.parse($0.text).hunks } ?? []
                    return (index, ConflictFile(path: path, resolved: found.isEmpty, conflicts: found.count))
                }
            }
            var collected: [(Int, ConflictFile)] = []
            for await pair in group { collected.append(pair) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }
}
