import Foundation
import Testing
@testable import gitForge

@Suite("HostingHTTP")
struct HostingHTTPTests {
    let server = StubServer()

    @Test("A connection cut by the trust delegate is a certificate error, not a cancellation")
    func pinMismatch() async {
        server.fail("GET", "/api/v4/user", with: .cancelled)
        await #expect(throws: HostingAuthError.tls(HostingHTTP.pinMismatch)) {
            _ = try await server.http.get(URL(string: "https://\(server.host)/api/v4/user")!, token: nil)
        }
    }

    @Test("Cancelled by the caller stays a cancellation")
    func callerCancelled() async {
        server.fail("GET", "/api/v4/user", with: .cancelled)
        let http = server.http
        let url = URL(string: "https://\(server.host)/api/v4/user")!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await http.get(url, token: nil)
        }
        await #expect(throws: HostingAuthError.cancelled) { _ = try await task.value }
    }
}
