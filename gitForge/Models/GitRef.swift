import Foundation

nonisolated struct GitRef: Sendable, Equatable, Identifiable, Hashable {
    enum Kind: Sendable, Equatable, Hashable {
        case localBranch
        case remoteBranch(remote: String)
        case tag
    }

    let name: String
    let kind: Kind
    let targetSha: String
    let isHead: Bool

    var id: String {
        switch kind {
        case .localBranch: "local:\(name)"
        case .remoteBranch(let remote): "remote:\(remote):\(name)"
        case .tag: "tag:\(name)"
        }
    }

    var displayName: String {
        switch kind {
        case .localBranch, .tag:
            return name
        case .remoteBranch(let remote):
            let prefix = "\(remote)/"
            return name.hasPrefix(prefix) ? String(name.dropFirst(prefix.count)) : name
        }
    }

    var isLocalBranch: Bool {
        if case .localBranch = kind { return true } else { return false }
    }

    var isRemoteBranch: Bool {
        if case .remoteBranch = kind { return true } else { return false }
    }

    var isTag: Bool {
        if case .tag = kind { return true } else { return false }
    }
}
