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
/// same host share one load. A read that `load` says not to keep (a request
/// failed: offline, an expired token, a failed probe) is used once, so the
/// next detail tries again.
actor GitLabInstanceInfoCache {
    static let shared = GitLabInstanceInfoCache()

    private var known: [String: GitLabInstanceInfo] = [:]
    private var loading: [String: Task<(info: GitLabInstanceInfo, keep: Bool), Never>] = [:]

    func info(for host: String,
              load: @escaping @Sendable () async -> (info: GitLabInstanceInfo, keep: Bool)) async -> GitLabInstanceInfo {
        if let info = known[host] { return info }
        if let task = loading[host] { return await task.value.info }
        let task = Task { await load() }
        loading[host] = task
        let loaded = await task.value
        if loaded.keep { known[host] = loaded.info }
        loading[host] = nil
        return loaded.info
    }

    func reset() {
        known = [:]
        loading = [:]
    }
}
