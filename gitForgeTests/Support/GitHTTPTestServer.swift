import Foundation
import Network
@testable import gitForge

/// A git smart-HTTP server for tests: 127.0.0.1 only, Basic auth (or none), and each
/// authorised request runs `git http-backend` (CGI) against the bare repos
/// under `root`. Records the `Authorization` header of every request, so
/// tests can tell which credential (if any) git sent.
final class GitHTTPTestServer: @unchecked Sendable {
    let root: URL
    /// `nil`: anonymous, every request is served.
    private let expectedAuthorization: String?
    private let listener: NWListener
    private let queue = DispatchQueue(label: "GitHTTPTestServer")
    private let lock = NSLock()
    private var seen: [String?] = []
    private var boundPort: UInt16 = 0

    /// No username: an anonymous server (like a public repo's).
    init(username: String? = nil, password: String = "") throws {
        root = TemporaryDirectories.make("gitForge-http")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        expectedAuthorization = username.map { "Basic " + Data("\($0):\(password)".utf8).base64EncodedString() }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    var baseURL: String { "http://127.0.0.1:\(lock.withLock { boundPort })" }

    func url(_ repo: String) -> String { "\(baseURL)/\(repo)" }

    /// `Authorization` header of each request so far (`nil` = none sent).
    var authorizations: [String?] { lock.withLock { seen } }

    func start() async throws {
        listener.newConnectionHandler = { [self] connection in
            connection.start(queue: queue)
            receive(on: connection, buffer: Data())
        }
        let once = Once()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    let port = listener.port?.rawValue ?? 0
                    lock.withLock { boundPort = port }
                    if once.claim() { continuation.resume() }
                case .failed(let error):
                    if once.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        try? FileManager.default.removeItem(at: root)
    }

    /// An empty bare repo at `root/<name>`. `git init` runs on a GCD thread,
    /// off the caller's cooperative thread (see `GitTestRepo`).
    @discardableResult
    func makeBareRepo(_ name: String) async throws -> URL {
        let path = root.appendingPathComponent(name)
        let result: Result<Void, Error> = await GitProcess.offPool {
            Result {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                process.arguments = ["git", "init", "-q", "--bare", "-b", "main", path.path]
                var environment = ProcessInfo.processInfo.environment
                environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
                environment["GIT_CONFIG_NOSYSTEM"] = "1"
                process.environment = environment
                // Not `waitUntilExit()`; see `GitTestRepo.git(_:allowFailure:)`.
                let exited = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in exited.signal() }
                try process.run()
                exited.wait()
            }
        }
        try result.get()
        return path
    }

    // MARK: HTTP

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Request.parse(buffer) {
                respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: Request, on connection: NWConnection) {
        let authorization = request.headers["authorization"]
        lock.withLock { seen.append(authorization) }
        guard expectedAuthorization == nil || authorization == expectedAuthorization else {
            send(status: "401 Unauthorized", headers: ["WWW-Authenticate": "Basic realm=\"test\""], body: Data(), on: connection)
            return
        }
        DispatchQueue.global().async { [self] in
            let (status, headers, body) = runBackend(request)
            send(status: status, headers: headers, body: body, on: connection)
        }
    }

    private func send(status: String, headers: [String: String], body: Data, on connection: NWConnection) {
        var head = "HTTP/1.1 \(status)\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// One CGI run of `git http-backend`.
    private func runBackend(_ request: Request) -> (String, [String: String], Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "http-backend"]
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        environment["GIT_PROJECT_ROOT"] = root.path
        environment["GIT_HTTP_EXPORT_ALL"] = "1"
        environment["REQUEST_METHOD"] = request.method
        environment["PATH_INFO"] = request.path
        environment["QUERY_STRING"] = request.query
        environment["CONTENT_TYPE"] = request.headers["content-type"] ?? ""
        environment["CONTENT_LENGTH"] = String(request.body.count)
        environment["REMOTE_USER"] = "test-user"
        environment["REMOTE_ADDR"] = "127.0.0.1"
        if let encoding = request.headers["content-encoding"] { environment["HTTP_CONTENT_ENCODING"] = encoding }
        if let gitProtocol = request.headers["git-protocol"] { environment["GIT_PROTOCOL"] = gitProtocol }
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return ("500 Internal Server Error", [:], Data()) }
        let body = request.body
        DispatchQueue.global().async {
            input.fileHandleForWriting.write(body)
            try? input.fileHandleForWriting.close()
        }
        let raw = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Self.parseCGI(raw)
    }

    private static func parseCGI(_ raw: Data) -> (String, [String: String], Data) {
        let separator = raw.range(of: Data("\r\n\r\n".utf8)) ?? raw.range(of: Data("\n\n".utf8))
        guard let separator else { return ("200 OK", [:], raw) }
        var status = "200 OK"
        var headers: [String: String] = [:]
        for line in String(decoding: raw[..<separator.lowerBound], as: UTF8.self).split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if name.lowercased() == "status" { status = value } else { headers[name] = value }
        }
        return (status, headers, Data(raw[separator.upperBound...]))
    }

    struct Request {
        var method: String
        var path: String
        var query: String
        /// Lowercased names.
        var headers: [String: String]
        var body: Data

        /// `nil` until the whole request (headers and body) has arrived.
        static func parse(_ data: Data) -> Request? {
            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            var lines = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let requestLine = lines.removeFirst().split(separator: " ")
            guard requestLine.count >= 2 else { return nil }
            var headers: [String: String] = [:]
            for line in lines {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let rest = Data(data[headerEnd.upperBound...])
            let body: Data
            if headers["transfer-encoding"]?.lowercased() == "chunked" {
                guard let decoded = decodeChunked(rest) else { return nil }
                body = decoded
            } else {
                let length = Int(headers["content-length"] ?? "0") ?? 0
                guard rest.count >= length else { return nil }
                body = rest.prefix(length)
            }
            let target = String(requestLine[1])
            let parts = target.split(separator: "?", maxSplits: 1).map(String.init)
            return Request(method: String(requestLine[0]), path: parts[0], query: parts.count > 1 ? parts[1] : "",
                           headers: headers, body: body)
        }

        /// `nil` until the final zero-length chunk has arrived.
        private static func decodeChunked(_ data: Data) -> Data? {
            var output = Data()
            var index = data.startIndex
            let crlf = Data("\r\n".utf8)
            while true {
                guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else { return nil }
                let sizeText = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
                    .split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
                guard let size = Int(sizeText, radix: 16) else { return nil }
                if size == 0 { return output }
                let start = lineEnd.upperBound
                guard data.distance(from: start, to: data.endIndex) >= size + 2 else { return nil }
                let end = data.index(start, offsetBy: size)
                output.append(data[start..<end])
                index = data.index(end, offsetBy: 2)
            }
        }
    }
}

/// Lets exactly one of several callbacks resume a continuation.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
