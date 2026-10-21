import Foundation

/// What a GitLab instance supports for reviews, read once per host.
nonisolated struct GitLabInstanceInfo: Sendable, Equatable {
    /// `nil` when `/version` couldn't be read.
    let version: GitLabVersion?
    /// The GraphQL schema has `mergeRequestRequestChanges`.
    let hasRequestChangesMutation: Bool

    /// Nothing known: treated as the oldest instance.
    static let unknown = GitLabInstanceInfo(version: nil, hasRequestChangesMutation: false)
}

/// Instance info per host for the app's lifetime. Concurrent asks for the
/// same host share one load.
actor GitLabInstanceInfoCache {
    static let shared = GitLabInstanceInfoCache()

    private var known: [String: GitLabInstanceInfo] = [:]
    private var loading: [String: Task<GitLabInstanceInfo, Never>] = [:]

    func info(for host: String, load: @escaping @Sendable () async -> GitLabInstanceInfo) async -> GitLabInstanceInfo {
        if let info = known[host] { return info }
        if let task = loading[host] { return await task.value }
        let task = Task { await load() }
        loading[host] = task
        let info = await task.value
        known[host] = info
        loading[host] = nil
        return info
    }

    func reset() {
        known = [:]
        loading = [:]
    }
}
