import Foundation
@testable import gitForge

/// Device-flow clock for tests: sleeping only advances virtual time and
/// records how long each wait was.
final class VirtualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: TimeInterval = 0
    private var waits: [Int] = []
    let start = Date(timeIntervalSince1970: 1_000_000)

    var sleeps: [Int] { lock.withLock { waits } }

    var clock: DeviceFlowClock {
        DeviceFlowClock(
            now: { [self] in lock.withLock { start.addingTimeInterval(elapsed) } },
            sleep: { [self] duration in
                let seconds = Int(duration.components.seconds)
                lock.withLock {
                    waits.append(seconds)
                    elapsed += TimeInterval(seconds)
                }
            })
    }
}

extension DeviceFlowClock {
    /// Real time, but each wait is 5 ms: for flows driven through a session.
    static let fast = DeviceFlowClock(now: { Date() }, sleep: { _ in try await Task.sleep(for: .milliseconds(5)) })
}
