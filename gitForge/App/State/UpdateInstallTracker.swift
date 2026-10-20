import Foundation

/// Remembers which update Sparkle was about to install, so the next launch
/// can tell whether it actually landed.
///
/// Sparkle's installer can fail after the app has quit (on macOS 26 the
/// first attempt sometimes gets `EACCES` moving the old bundle out of
/// `/Applications`) and it reports nothing: the app just doesn't come back
/// updated. A fresh attempt right after relaunching works, so a launch that
/// finds the old version still running retries once, then gives up and
/// tells the user.
nonisolated struct UpdateInstallTracker {
    enum LaunchOutcome: Equatable {
        /// No install was pending.
        case none
        /// The pending update is now the running version.
        case installed(version: String)
        /// The pending update didn't land; retry it now.
        case retry(version: String)
        /// It didn't land after the retry either; stop and tell the user.
        case failed(version: String)
    }

    /// Automatic retries per version before giving up.
    static let maxRetries = 1

    static let pendingVersionKey = "updates.pendingInstallVersion"
    static let attemptsKey = "updates.pendingInstallAttempts"

    let defaults: UserDefaults
    /// Orders two `CFBundleVersion`s; Sparkle's own comparator in the app.
    let compare: @Sendable (_ lhs: String, _ rhs: String) -> ComparisonResult

    /// Called when Sparkle is about to install `version` (now or on quit).
    /// Re-recording the same version keeps its retry count.
    func recordPendingInstall(version: String) {
        guard defaults.string(forKey: Self.pendingVersionKey) != version else { return }
        defaults.set(version, forKey: Self.pendingVersionKey)
        defaults.set(0, forKey: Self.attemptsKey)
    }

    /// Decides what to do about a pending install at launch. Every outcome
    /// except `.retry` clears the record, so this never loops.
    func evaluateLaunch(currentVersion: String) -> LaunchOutcome {
        guard let pending = defaults.string(forKey: Self.pendingVersionKey) else { return .none }
        if compare(currentVersion, pending) != .orderedAscending {
            clear()
            return .installed(version: pending)
        }
        let attempts = defaults.integer(forKey: Self.attemptsKey)
        guard attempts < Self.maxRetries else {
            clear()
            return .failed(version: pending)
        }
        defaults.set(attempts + 1, forKey: Self.attemptsKey)
        return .retry(version: pending)
    }

    func clear() {
        defaults.removeObject(forKey: Self.pendingVersionKey)
        defaults.removeObject(forKey: Self.attemptsKey)
    }
}
