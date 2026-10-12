import Foundation
import Testing
@testable import gitForge

/// Scripted answers for the token endpoint, one per attempt.
private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [Result<DevicePollOutcome, HostingAuthError>]
    private(set) var attempts = 0

    init(_ outcomes: [Result<DevicePollOutcome, HostingAuthError>]) { self.outcomes = outcomes }

    func next() throws -> DevicePollOutcome {
        let outcome = lock.withLock {
            attempts += 1
            return outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        }
        return try outcome.get()
    }
}

@Suite("Device flow — waiting for approval")
struct DeviceFlowPollerTests {
    private static let grant = TokenGrant(accessToken: "test-access", refreshToken: nil, expiresIn: nil, scopes: nil)

    private func code(expiresIn: Int = 900, interval: Int = 5) -> DeviceCode {
        DeviceCode(deviceCode: "d", userCode: "U", verificationURI: URL(string: "https://example.test/device")!,
                   verificationURIComplete: nil, expiresIn: expiresIn, interval: interval)
    }

    @Test("Pending keeps waiting at the interval until the token arrives")
    func pendingThenGranted() async throws {
        let clock = VirtualClock()
        let script = Script([.success(.pending), .success(.pending), .success(.granted(Self.grant))])
        let grant = try await DeviceFlowPoller.run(code: code(), clock: clock.clock) { try script.next() }
        #expect(grant == Self.grant)
        #expect(clock.sleeps == [5, 5, 5])
    }

    @Test("slow_down adds 5 s for the rest of the wait")
    func slowDown() async throws {
        let clock = VirtualClock()
        let script = Script([.success(.slowDown(interval: nil)), .success(.pending), .success(.granted(Self.grant))])
        _ = try await DeviceFlowPoller.run(code: code(), clock: clock.clock) { try script.next() }
        #expect(clock.sleeps == [5, 10, 10])
    }

    @Test("A longer interval sent with slow_down wins")
    func slowDownServerInterval() async throws {
        let clock = VirtualClock()
        let script = Script([.success(.slowDown(interval: 30)), .success(.granted(Self.grant))])
        _ = try await DeviceFlowPoller.run(code: code(), clock: clock.clock) { try script.next() }
        #expect(clock.sleeps == [5, 30])
    }

    @Test("Past the code's lifetime it stops with expiredToken, without another poll")
    func expires() async {
        let clock = VirtualClock()
        let script = Script([.success(.pending)])
        await #expect(throws: HostingAuthError.expiredToken) {
            try await DeviceFlowPoller.run(code: self.code(expiresIn: 12), clock: clock.clock) { try script.next() }
        }
        #expect(script.attempts == 2)
    }

    @Test("Terminal errors from the server end the wait")
    func denied() async {
        let script = Script([.success(.pending), .failure(.accessDenied)])
        await #expect(throws: HostingAuthError.accessDenied) {
            try await DeviceFlowPoller.run(code: self.code(), clock: VirtualClock().clock) { try script.next() }
        }
        #expect(script.attempts == 2)
    }

    @Test("Cancelling the wait ends it as cancelled")
    func cancelled() async {
        let clock = DeviceFlowClock(now: { Date() }, sleep: { _ in throw CancellationError() })
        let script = Script([.success(.pending)])
        await #expect(throws: HostingAuthError.cancelled) {
            try await DeviceFlowPoller.run(code: self.code(), clock: clock) { try script.next() }
        }
        #expect(script.attempts == 0)
    }

    @Test("A network blip or a server error keeps waiting")
    func transientErrors() async throws {
        let clock = VirtualClock()
        let script = Script([.failure(.network("offline")), .failure(.server(502)), .success(.granted(Self.grant))])
        let grant = try await DeviceFlowPoller.run(code: code(), clock: clock.clock) { try script.next() }
        #expect(grant == Self.grant)
        #expect(script.attempts == 3)
    }

    @Test("Network errors until the code's lifetime ends: expiredToken")
    func transientUntilExpiry() async {
        let clock = VirtualClock()
        let script = Script([.failure(.network("offline"))])
        await #expect(throws: HostingAuthError.expiredToken) {
            try await DeviceFlowPoller.run(code: self.code(expiresIn: 12), clock: clock.clock) { try script.next() }
        }
    }
}
