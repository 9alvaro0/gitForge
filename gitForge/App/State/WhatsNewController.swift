import Foundation
import Observation

/// Owns the What's New sheet: decides once per launch whether it shows,
/// opens it from the Help menu, and hands it to whichever window presents
/// it first.
@Observable
@MainActor
final class WhatsNewController {
    /// A presentation waiting for a window to show it.
    private(set) var pending: WhatsNewPresentation?
    /// This launch shows the sheet, so the "Updated to" toast is redundant.
    private(set) var showsSheetThisLaunch = false

    @ObservationIgnored private let catalog: WhatsNewCatalog
    @ObservationIgnored private let gate: WhatsNewGate
    @ObservationIgnored private let currentVersion: String
    @ObservationIgnored private var evaluated = false

    /// Creating it touches no defaults; only `evaluateAtLaunch` does.
    init(catalog: WhatsNewCatalog = .bundled,
         gate: WhatsNewGate = .standard,
         currentVersion: String = WhatsNewController.bundleVersion) {
        self.catalog = catalog
        self.gate = gate
        self.currentVersion = currentVersion
    }

    static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var canShowFromMenu: Bool {
        latestRelease != nil
    }

    /// Runs the launch rule once per controller, even if several windows
    /// appear.
    func evaluateAtLaunch() {
        guard !evaluated else { return }
        evaluated = true
        pending = gate.evaluate(currentVersion: currentVersion, catalog: catalog)
        showsSheetThisLaunch = pending != nil
    }

    /// Help › What's New in gitForge: the newest notes up to this version.
    func showFromMenu() {
        guard pending == nil, let release = latestRelease else { return }
        pending = WhatsNewPresentation(currentVersion: release.version, previousVersion: nil,
                                       releases: [release], source: .menu)
    }

    /// Hands the pending presentation to the window that asks first, unless
    /// that window already shows another sheet. The launch sheet marks its
    /// version seen here, so quitting with it open doesn't bring it back.
    func claim(otherSheetUp: Bool) -> WhatsNewPresentation? {
        guard !otherSheetUp, let presentation = pending else { return nil }
        pending = nil
        if presentation.source == .launch {
            gate.markSeen(currentVersion)
        }
        return presentation
    }

    private var latestRelease: WhatsNewRelease? {
        catalog.latestWithHighlights(upTo: currentVersion, compare: gate.compare)
    }
}
