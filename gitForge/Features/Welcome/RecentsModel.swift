import Foundation
import Observation

/// What Welcome shows next to each recent repository.
nonisolated enum RecentState: Equatable, Sendable {
    case loading
    case ready(RecentRepoSummary)
    /// The folder is gone or isn't a repository any more.
    case missing
}

/// Reads branch and status of Welcome's recents, a few at a time, without
/// taking optional locks in repos the user isn't looking at.
@MainActor
@Observable
final class RecentsModel {
    static let concurrency = 4

    private(set) var states: [URL: RecentState] = [:]
    /// `nil`: no answer (the read was cancelled).
    @ObservationIgnored private let read: @Sendable (URL) async -> RecentState?

    init(read: @escaping @Sendable (URL) async -> RecentState? = RecentsModel.readFromDisk) {
        self.read = read
    }

    func load(_ repositories: [Repository]) async {
        let urls = repositories.map(\.url).filter { states[$0] == nil }
        for url in urls { states[url] = .loading }
        let read = self.read
        await withTaskGroup(of: (URL, RecentState?).self) { group in
            var pending = urls[...]
            func startNext() {
                guard !Task.isCancelled, let url = pending.popFirst() else { return }
                group.addTask { (url, await read(url)) }
            }
            for _ in 0..<Self.concurrency { startNext() }
            for await (url, state) in group {
                states[url] = state
                startNext()
            }
        }
        // Cancelled half-way: what wasn't read stays unknown, so the next
        // load reads it.
        for url in urls where states[url] == .loading { states[url] = nil }
    }

    @Sendable
    nonisolated static func readFromDisk(_ url: URL) async -> RecentState? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue else { return .missing }
        do {
            let result = try await GitCLI(workingDirectory: url)
                .run(["--no-optional-locks", "status", "--porcelain=v1", "--branch"])
            return .ready(RecentRepoSummary.parse(result.stdout))
        } catch {
            return Task.isCancelled || error is CancellationError ? nil : .missing
        }
    }
}
