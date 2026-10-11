import Foundation
@testable import gitForge

/// A fake HTTP server for one test. Requests to its host never leave the
/// process: `StubURLProtocol` answers them from responses queued with `on`.
/// Each server has its own random host, so parallel tests never share routes.
final class StubServer: @unchecked Sendable {
    struct Response {
        var status: Int
        var headers: [String: String]
        var body: Data
    }

    struct Request {
        var method: String
        var path: String
        var headers: [String: String]
        /// Fields of a form-encoded body.
        var form: [String: String]

        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    let host = "stub-\(UUID().uuidString.lowercased()).test"
    let http: HostingHTTP
    private let lock = NSLock()
    private var routes: [String: [Response]] = [:]
    private var log: [Request] = []

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        http = HostingHTTP(session: URLSession(configuration: config))
        StubURLProtocol.register(self)
    }

    /// Queues an answer for `method path` from `Fixtures/Accounts/<fixture>.json`.
    /// Answers are served in order; the last one repeats.
    func on(_ method: String, _ path: String, status: Int = 200, headers: [String: String] = [:], fixture: String) {
        on(method, path, status: status, headers: headers, body: Fixture.data(fixture))
    }

    func on(_ method: String, _ path: String, status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
        var headers = headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json" }
        let response = Response(status: status, headers: headers, body: body)
        lock.withLock { routes["\(method) \(path)", default: []].append(response) }
    }

    var requests: [Request] { lock.withLock { log } }

    func requests(_ method: String, _ path: String) -> [Request] {
        requests.filter { $0.method == method && $0.path == path }
    }

    fileprivate func answer(_ request: URLRequest) -> Response {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let recorded = Request(method: method, path: path, headers: request.allHTTPHeaderFields ?? [:],
                               form: Self.form(StubURLProtocol.body(of: request)))
        let key = "\(method) \(path)"
        return lock.withLock {
            log.append(recorded)
            guard var queue = routes[key], let first = queue.first else {
                return Response(status: 404, headers: [:], body: Data("no stub for \(key)".utf8))
            }
            if queue.count > 1 {
                queue.removeFirst()
                routes[key] = queue
            }
            return first
        }
    }

    private static func form(_ body: Data) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        return fields
    }
}

/// Answers every request from the `StubServer` registered for its host.
final class StubURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [String: StubServer] = [:]

    static func register(_ server: StubServer) {
        lock.withLock { servers[server.host] = server }
    }

    private static func server(for host: String?) -> StubServer? {
        lock.withLock { host.flatMap { servers[$0] } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let server = Self.server(for: url.host) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = server.answer(request)
        let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: "HTTP/1.1",
                                   headerFields: response.headers)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// URLSession hands protocols the body as a stream.
    static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// JSON files in `gitForgeTests/Fixtures/`, copied flat into the test bundle.
enum Fixture {
    static func data(_ name: String) -> Data {
        guard let url = Bundle(for: StubURLProtocol.self).url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            preconditionFailure("Fixture \(name).json isn't in the test bundle")
        }
        return data
    }
}
