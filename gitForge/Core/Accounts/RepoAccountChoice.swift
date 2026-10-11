import Foundation

/// What a repo remote signs with (P4 spec §4.1): a given account, or the
/// system's credentials (gitForge stays out and git uses its own helper).
nonisolated enum RepoAccountChoice: Codable, Equatable, Hashable, Sendable {
    case account(UUID)
    case system

    var accountId: UUID? {
        if case .account(let id) = self { id } else { nil }
    }
}
