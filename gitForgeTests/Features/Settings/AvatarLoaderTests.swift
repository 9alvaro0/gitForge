import AppKit
import Foundation
import Testing
@testable import gitForge

@Suite("AvatarLoader", .serialized)
@MainActor
struct AvatarLoaderTests {
    private func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        return rep.representation(using: .png, properties: [:])!
    }

    @Test("Avatars load through the given session and are fetched once")
    func loadsAndCaches() async throws {
        let server = StubServer()
        server.on("GET", "/u/1.png", headers: ["Content-Type": "image/png"], body: pngData())
        let loader = AvatarLoader(http: server.http)
        let url = try #require(URL(string: "https://\(server.host)/u/1.png"))
        #expect(await loader.image(for: url) != nil)
        #expect(await loader.image(for: url) != nil)
        #expect(server.requests("GET", "/u/1.png").count == 1)
    }

    @Test("A failed or non-image answer gives no image")
    func failures() async throws {
        let server = StubServer()
        server.on("GET", "/u/2.png", status: 404, body: Data())
        server.on("GET", "/u/3.png", body: Data("not an image".utf8))
        let loader = AvatarLoader(http: server.http)
        #expect(await loader.image(for: URL(string: "https://\(server.host)/u/2.png")!) == nil)
        #expect(await loader.image(for: URL(string: "https://\(server.host)/u/3.png")!) == nil)
    }
}
