import Foundation

/// Polls `condition` on the main actor until it holds or `timeout` passes.
/// It returns as soon as the condition holds, so the generous default only
/// costs time when a test is failing anyway: on a loaded CI runner (the
/// whole suite runs in parallel) 3 s wasn't enough for the device flow
/// tests' stub-server round trips.
@MainActor
func waitUntil(timeout: Duration = .seconds(15), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
