import Foundation
import Observation
import Sparkle

/// Observable wrapper around `SPUStandardUpdaterController`.
///
/// Sparkle checks every few hours, downloads updates in the background and
/// installs them when the app quits (`SUAutomaticallyUpdate`). On top of
/// that this type:
/// - exposes a downloaded update (`readyUpdate`) so the toolbar can offer
///   "Restart to Update" instead of waiting for the user to quit;
/// - detects an install that silently failed after quitting and retries it
///   once on the next launch (`UpdateInstallTracker`);
/// - reports the result once per launch (`launchNotice`) for a toast.
@Observable
@MainActor
final class Updater {
    struct ReadyUpdate: Equatable {
        let version: String
    }

    enum LaunchNotice: Equatable {
        case installed(version: String)
        case failed(version: String)
    }

    /// Where users download a build by hand when updating keeps failing.
    static let releasesURL = URL(string: "https://github.com/9alvaro0/gitForge/releases/latest")!

    private(set) var canCheckForUpdates: Bool
    /// A downloaded update waiting to be installed.
    private(set) var readyUpdate: ReadyUpdate?
    /// Outcome of the previous launch's install, shown once.
    var launchNotice: LaunchNotice?
    /// Download and install updates without asking (Sparkle's
    /// `automaticallyDownloadsUpdates`, persisted by Sparkle).
    private(set) var installsUpdatesAutomatically: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let delegate: Delegate
    @ObservationIgnored private let tracker: UpdateInstallTracker
    @ObservationIgnored private var installNow: (() -> Void)?
    /// Set while retrying an install that failed: install as soon as the
    /// update is ready instead of waiting for the user.
    @ObservationIgnored private var retrying = false
    @ObservationIgnored private var observation: NSKeyValueObservation?
    /// `evaluateLaunch` spends a retry, so it must run once per process even
    /// if SwiftUI builds the app struct (and this initial value) twice.
    private static var handledLaunch = false

    init(defaults: UserDefaults = .standard) {
        let tracker = UpdateInstallTracker(defaults: defaults) { lhs, rhs in
            SUStandardVersionComparator.default.compareVersion(lhs, toVersion: rhs)
        }
        let delegate = Delegate()
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        self.tracker = tracker
        self.delegate = delegate
        self.controller = controller
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.installsUpdatesAutomatically = controller.updater.automaticallyDownloadsUpdates

        // Sparkle holds its delegate weakly; `self.delegate` keeps it alive.
        delegate.onWillInstall = { [weak self] version in
            self?.tracker.recordPendingInstall(version: version)
        }
        delegate.onReadyToInstall = { [weak self] version, install in
            self?.updateReady(version: version, install: install)
        }

        self.observation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.new]
        ) { [weak self] _, change in
            let next = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = next
            }
        }

        handlePreviousInstall()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setInstallsUpdatesAutomatically(_ enabled: Bool) {
        controller.updater.automaticallyDownloadsUpdates = enabled
        installsUpdatesAutomatically = enabled
    }

    /// Installs the downloaded update and relaunches the app.
    func installAndRelaunch() {
        installNow?()
    }

    private func handlePreviousInstall() {
        guard !Self.handledLaunch else { return }
        Self.handledLaunch = true
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        switch tracker.evaluateLaunch(currentVersion: current) {
        case .none:
            break
        case .installed(let version):
            launchNotice = .installed(version: version)
        case .failed(let version):
            launchNotice = .failed(version: version)
        case .retry:
            // Same run loop turn as `startUpdater`, so this replaces the
            // launch check. An already downloaded update is resumed and
            // comes back through `updateReady`.
            retrying = true
            controller.updater.checkForUpdatesInBackground()
        }
    }

    private func updateReady(version: String, install: @escaping () -> Void) {
        // Recorded here too: Sparkle installs on quit even if the user never
        // presses Restart, and that install is the one that can fail.
        tracker.recordPendingInstall(version: version)
        installNow = install
        readyUpdate = ReadyUpdate(version: version)
        if retrying {
            retrying = false
            install()
        }
    }
}

private extension Updater {
    final class Delegate: NSObject, SPUUpdaterDelegate {
        var onWillInstall: ((String) -> Void)?
        var onReadyToInstall: ((String, @escaping () -> Void) -> Void)?

        func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
            onWillInstall?(item.versionString)
        }

        /// Returning `true` keeps the update for our own "Restart to Update"
        /// button. Sparkle still installs it when the app quits.
        func updater(_ updater: SPUUpdater,
                     willInstallUpdateOnQuit item: SUAppcastItem,
                     immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
            onReadyToInstall?(item.versionString, immediateInstallHandler)
            return true
        }
    }
}
