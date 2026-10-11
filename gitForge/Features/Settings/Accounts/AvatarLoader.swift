import AppKit
import Foundation

/// Account avatars, fetched through the pinned-trust session (P4 spec §8:
/// `AsyncImage` would fail on an instance with a private certificate) and
/// kept in memory for the app's lifetime.
@MainActor
final class AvatarLoader {
    static let shared = AvatarLoader()

    private let http: HostingHTTP
    private var cache: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data?, Never>] = [:]

    init(http: HostingHTTP = .live) {
        self.http = http
    }

    func image(for url: URL) async -> NSImage? {
        if let data = cache[url] { return NSImage(data: data) }
        let task: Task<Data?, Never>
        if let running = inFlight[url] {
            task = running
        } else {
            let http = self.http
            task = Task {
                guard let (data, response) = try? await http.send(URLRequest(url: url)),
                      (200..<300).contains(response.statusCode) else { return nil }
                return data
            }
            inFlight[url] = task
        }
        let data = await task.value
        inFlight[url] = nil
        guard let data, let image = NSImage(data: data) else { return nil }
        cache[url] = data
        return image
    }
}
