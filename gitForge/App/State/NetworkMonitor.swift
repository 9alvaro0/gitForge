import Foundation
import Network
import Observation

/// Whether the Mac currently has a usable network path. Drives the
/// online/offline indicators (status bar, sidebar user card), which used to
/// be hard-coded to "online".
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isOnline = true

    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.warwarelabs.gitForge.network", qos: .utility))
    }

    deinit {
        monitor.cancel()
    }
}
