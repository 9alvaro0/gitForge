import Foundation

/// Time for the device-flow wait; tests swap in a virtual clock.
nonisolated struct DeviceFlowClock: Sendable {
    var now: @Sendable () -> Date
    var sleep: @Sendable (Duration) async throws -> Void

    static let live = DeviceFlowClock(now: { Date() }, sleep: { try await Task.sleep(for: $0) })
}

/// Waits for the user to approve a device code (spec §5.1): one poll every
/// `interval` seconds, 5 more after each `slow_down`, until a token, a
/// terminal error, cancellation or the code's expiry. A network blip or a
/// server error counts as "still pending": the wait can last 15 minutes.
nonisolated enum DeviceFlowPoller {
    static let slowDownStep = 5

    static func run(code: DeviceCode, clock: DeviceFlowClock,
                    attempt: () async throws -> DevicePollOutcome) async throws -> TokenGrant {
        let deadline = clock.now().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = max(code.interval, 1)
        while true {
            do {
                try await clock.sleep(.seconds(interval))
            } catch {
                throw HostingAuthError.cancelled
            }
            if Task.isCancelled { throw HostingAuthError.cancelled }
            guard clock.now() < deadline else { throw HostingAuthError.expiredToken }
            let outcome: DevicePollOutcome
            do {
                outcome = try await attempt()
            } catch HostingAuthError.network, HostingAuthError.server {
                continue
            }
            switch outcome {
            case .granted(let grant):
                return grant
            case .pending:
                continue
            case .slowDown(let serverInterval):
                interval = max(interval + slowDownStep, serverInterval ?? 0)
            }
        }
    }
}

nonisolated extension HostingAuthClient {
    /// Polls the token endpoint until the user approves `code` in the browser.
    func pollToken(clientId: String, code: DeviceCode, clock: DeviceFlowClock = .live) async throws -> TokenGrant {
        try await DeviceFlowPoller.run(code: code, clock: clock) {
            try await pollTokenOnce(clientId: clientId, deviceCode: code.deviceCode)
        }
    }
}
