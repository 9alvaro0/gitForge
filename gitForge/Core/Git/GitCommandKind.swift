import Foundation

/// What a git invocation does, as far as the idle watchdog cares. Decides how
/// long a silent command may run and what the user is told when it's killed.
///
/// The watchdog exists for network commands: a DNS hang or an askpass
/// deadlock prints nothing, so it dies quickly. Commands that commit run the
/// repository's local hooks (`pre-commit`, `commit-msg`…), which may run a
/// test suite or a linter that prints nothing for minutes. Killing those at
/// the network timeout lost the commit and blamed the remote (#58).
nonisolated enum GitCommandKind: Sendable, Equatable {
    /// Talks to a remote: the configured idle timeout, network wording.
    case network
    /// Creates commits and so runs local hooks: a long idle ceiling, local wording.
    case runsHooks
    /// Everything else: the configured idle timeout, local wording.
    case local

    /// Idle ceiling for commands that run hooks. Long enough for a slow test
    /// suite in a `pre-commit`, short enough that a hook stuck on a prompt
    /// the app can't answer doesn't hang the repository forever.
    static let hookIdleTimeout: TimeInterval = 30 * 60

    private static let networkSubcommands: Set<String> = ["fetch", "pull", "push", "ls-remote", "clone"]
    /// `git remote <sub>` forms that contact the remote.
    private static let networkRemoteSubcommands: Set<String> = ["update", "prune", "show"]
    /// Commit, plus the integrations whose commits (and `--continue`) run
    /// `pre-commit`, `pre-merge-commit`, `prepare-commit-msg` and `commit-msg`.
    private static let hookSubcommands: Set<String> = ["commit", "merge", "rebase", "cherry-pick", "revert", "am"]

    /// Classifies `arguments` as passed to `GitCLI.run` (no leading `git`).
    /// Leading `-c key=value` pairs are skipped to find the subcommand.
    init(arguments: [String]) {
        var rest = arguments[...]
        while let first = rest.first, first == "-c" {
            rest = rest.dropFirst(2)
        }
        guard let subcommand = rest.first else { self = .local; return }
        if Self.networkSubcommands.contains(subcommand) {
            self = .network
        } else if subcommand == "remote", let sub = rest.dropFirst().first,
                  Self.networkRemoteSubcommands.contains(sub) {
            self = .network
        } else if Self.hookSubcommands.contains(subcommand) {
            self = .runsHooks
        } else {
            self = .local
        }
    }

    /// Seconds without output before the watchdog kills the command.
    /// `configured` is the user's setting (Settings ▸ Behavior).
    func idleTimeout(configured: TimeInterval) -> TimeInterval {
        switch self {
        case .network, .local: configured
        case .runsHooks: max(configured, Self.hookIdleTimeout)
        }
    }

    /// Synthesised stderr when the watchdog killed a command that printed
    /// nothing. The network text stays English on purpose: it's phrased so
    /// `RemoteFailure(stderr:)` routes it to `.network`. The local text never
    /// mentions a remote and doesn't match any `RemoteFailure` bucket.
    func timeoutMessage(after timeout: TimeInterval) -> String {
        let seconds = Int(timeout)
        switch self {
        case .network:
            return "connection timed out after \(seconds)s — the remote may be unreachable, or git is stuck on something the app can't drive non-interactively."
        case .runsHooks, .local:
            return String(localized: "git printed nothing for \(seconds) s and was stopped. A hook or another program git started may be stuck or waiting for input the app can't provide.")
        }
    }
}
