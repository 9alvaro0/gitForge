import Foundation
import Observation
import Sparkle

/// Thin observable wrapper around `SPUStandardUpdaterController`.
///
/// Sparkle owns the update lifecycle (background checks, sheets, install).
/// This type only exposes `canCheckForUpdates` to SwiftUI so the menu item
/// can disable while a check is already in flight.
@Observable
@MainActor
final class Updater {
    private let controller: SPUStandardUpdaterController
    private(set) var canCheckForUpdates: Bool

    @ObservationIgnored
    private var observation: NSKeyValueObservation?

    init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.controller = controller
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.observation = controller.updater.observe(
            \.canCheckForUpdates,
            options: [.new]
        ) { [weak self] _, change in
            let next = change.newValue ?? false
            Task { @MainActor [weak self] in
                self?.canCheckForUpdates = next
            }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
