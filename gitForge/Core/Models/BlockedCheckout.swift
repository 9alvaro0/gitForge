import Foundation

/// What a checkout started from the UI moves HEAD to, kept so a refused
/// checkout can run again once the changes in its way are out of it.
nonisolated enum CheckoutTarget: Sendable, Equatable {
    /// A local branch, or a remote one git turns into a local tracking branch.
    case branch(GitRef)
    /// A commit: HEAD ends up detached there.
    case commit(sha: String)
    /// A pull request's source branch: the local one, or a new one tracking
    /// the remote branch.
    case pullRequestBranch(String)

    /// How the question and the toasts name it.
    var displayName: String {
        switch self {
        case .branch(let ref): ref.displayName
        case .commit(let sha): String(sha.prefix(7))
        case .pullRequestBranch(let name): name
        }
    }

    /// The toast once it's checked out.
    var successMessage: String {
        switch self {
        case .branch, .pullRequestBranch:
            String(localized: "Checked out \(displayName)")
        case .commit:
            String(localized: "Detached HEAD at \(displayName)")
        }
    }
}

/// A checkout git refused because local changes were in the way. The view
/// model publishes it instead of a failure; `ShellView` asks whether to
/// stash or discard `files` and check `target` out again.
nonisolated struct BlockedCheckout: Sendable, Equatable, Identifiable {
    let id = UUID()
    /// The files git named: tracked changes (staged or not) and untracked
    /// files the checkout would overwrite. Other changes aren't touched and
    /// come along to the new branch, as git carries them.
    let files: [WorkingCopyFile]
    let target: CheckoutTarget

    var title: String {
        let name = target.displayName
        return files.count == 1
            ? String(localized: "Your changes to 1 file block checking out \(name)")
            : String(localized: "Your changes to \(files.count) files block checking out \(name)")
    }

    /// The way out, then the files one per line.
    var message: String {
        let intro = String(localized: "Checking out \(target.displayName) would overwrite them. Stash them to get them back later, or discard them:")
        return ([intro] + DiscardFileList.lines(files)).joined(separator: "\n")
    }

    /// The stash's message, so it can be told apart in Stashes.
    var stashMessage: String {
        String(localized: "Before checking out \(target.displayName)")
    }
}
