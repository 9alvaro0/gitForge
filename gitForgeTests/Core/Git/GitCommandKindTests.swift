import Foundation
import Testing
@testable import gitForge

/// Which watchdog policy each git command gets (#58): network commands keep
/// the user's idle timeout; commands that run local hooks get a long ceiling;
/// only network commands blame the remote when the watchdog fires.
@Suite("GitCommandKind")
struct GitCommandKindTests {

    @Test("Network subcommands", arguments: [
        ["fetch", "--all", "--prune"], ["pull", "--ff-only"], ["push", "-u", "origin", "main"],
        ["ls-remote", "origin"], ["remote", "update"], ["remote", "show", "origin"],
        ["-c", "http.extraHeader=x", "fetch", "origin"],
    ])
    func network(_ args: [String]) {
        #expect(GitCommandKind(arguments: args) == .network)
    }

    @Test("Commit and the integrations that commit run hooks", arguments: [
        ["commit", "-m", "x"], ["commit", "--amend", "--no-verify", "-m", "x"],
        ["merge", "--continue"], ["rebase", "--continue"], ["cherry-pick", "--continue"], ["revert", "--continue"],
        ["merge", "--no-ff", "--end-of-options", "feature"], ["cherry-pick", "abc123"],
    ])
    func runsHooks(_ args: [String]) {
        #expect(GitCommandKind(arguments: args) == .runsHooks)
    }

    @Test("Everything else is local", arguments: [
        ["status", "--porcelain=v2"], ["remote"], ["remote", "get-url", "origin"], ["rev-parse", "HEAD"],
        ["checkout", "main"], [],
    ])
    func local(_ args: [String]) {
        #expect(GitCommandKind(arguments: args) == .local)
    }

    @Test("A silent 90 s pre-commit fits under the hook ceiling; network and local keep the setting")
    func idleTimeouts() {
        #expect(GitCommandKind.runsHooks.idleTimeout(configured: 60) > 90)
        #expect(GitCommandKind.runsHooks.idleTimeout(configured: 60) == GitCommandKind.hookIdleTimeout)
        // A user who set a longer timeout than the ceiling keeps theirs.
        #expect(GitCommandKind.runsHooks.idleTimeout(configured: 3600) == 3600)
        #expect(GitCommandKind.network.idleTimeout(configured: 60) == 60)
        #expect(GitCommandKind.local.idleTimeout(configured: 60) == 60)
    }

    @Test("Only the network timeout message mentions the remote and routes to .network")
    func timeoutMessages() {
        let network = GitCommandKind.network.timeoutMessage(after: 60)
        #expect(network.contains("remote"))
        #expect(RemoteFailure(stderr: network) == .network)
        for kind in [GitCommandKind.runsHooks, .local] {
            let message = kind.timeoutMessage(after: 1800)
            #expect(!message.localizedCaseInsensitiveContains("remote"))
            // `String(localized:)` formats the number for the locale ("1,800" in en_US).
            #expect(message.contains("1800") || message.contains(1800.formatted()))
            #expect(RemoteFailure(stderr: message) != .network)
        }
    }

    @Test("The watchdog's message follows its kind")
    func watchdogMessage() {
        #expect(GitWatchdog(timeout: 30).timeoutMessage.contains("remote"))
        #expect(!GitWatchdog(timeout: 30, kind: .runsHooks).timeoutMessage.contains("remote"))
    }
}
