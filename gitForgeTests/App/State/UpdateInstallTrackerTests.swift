import Foundation
import Testing
@testable import gitForge

@Suite("UpdateInstallTracker")
struct UpdateInstallTrackerTests {
    private func tracker(_ suite: TestDefaults) -> UpdateInstallTracker {
        UpdateInstallTracker(defaults: suite.defaults) { $0.compare($1, options: .numeric) }
    }

    @Test("Nothing pending: no outcome")
    func nothingPending() {
        TestDefaults.with { suite in
            #expect(tracker(suite).evaluateLaunch(currentVersion: "1.2.0") == .none)
        }
    }

    @Test("Running the pending version reports the install and clears it")
    func installed() {
        TestDefaults.with { suite in
            let tracker = tracker(suite)
            tracker.recordPendingInstall(version: "1.2.1")
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.1") == .installed(version: "1.2.1"))
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.1") == .none)
        }
    }

    @Test("A newer running version also counts as installed")
    func newerThanPending() {
        TestDefaults.with { suite in
            let tracker = tracker(suite)
            tracker.recordPendingInstall(version: "1.2.1")
            #expect(tracker.evaluateLaunch(currentVersion: "1.3.0") == .installed(version: "1.2.1"))
        }
    }

    @Test("Still on the old version: retry once, then fail and clear")
    func retryThenFail() {
        TestDefaults.with { suite in
            let tracker = tracker(suite)
            tracker.recordPendingInstall(version: "1.2.1")
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.0") == .retry(version: "1.2.1"))
            // The retry re-records the same version; that must not reset the count.
            tracker.recordPendingInstall(version: "1.2.1")
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.0") == .failed(version: "1.2.1"))
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.0") == .none)
        }
    }

    @Test("Successful retry reports the install")
    func retryThenInstalled() {
        TestDefaults.with { suite in
            let tracker = tracker(suite)
            tracker.recordPendingInstall(version: "1.2.1")
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.0") == .retry(version: "1.2.1"))
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.1") == .installed(version: "1.2.1"))
        }
    }

    @Test("A different pending version starts its own retry count")
    func newVersionResetsAttempts() {
        TestDefaults.with { suite in
            let tracker = tracker(suite)
            tracker.recordPendingInstall(version: "1.2.1")
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.0") == .retry(version: "1.2.1"))
            tracker.recordPendingInstall(version: "1.2.2")
            #expect(tracker.evaluateLaunch(currentVersion: "1.2.0") == .retry(version: "1.2.2"))
        }
    }

    @Test("Versions compare numerically, not as strings")
    func numericComparison() {
        TestDefaults.with { suite in
            let tracker = tracker(suite)
            tracker.recordPendingInstall(version: "1.10.0")
            #expect(tracker.evaluateLaunch(currentVersion: "1.9.0") == .retry(version: "1.10.0"))
        }
    }
}
