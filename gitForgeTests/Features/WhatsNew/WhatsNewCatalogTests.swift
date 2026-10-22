import AppKit
import Foundation
import Testing
@testable import gitForge

/// The test bundle ships no `whats-new.json`, so it stands in for a build
/// whose resource went missing.
private final class BundleToken {}

@Suite("WhatsNewCatalog")
struct WhatsNewCatalogTests {
    private let numeric: WhatsNewVersionCompare = { $0.compare($1, options: .numeric) }

    private func release(_ version: String, highlights: Int = 0) -> WhatsNewRelease {
        let text = LocalizedText(["en": "x"])
        return WhatsNewRelease(
            version: version,
            highlights: Array(repeating: WhatsNewHighlight(symbol: nil, title: text, body: text), count: highlights),
            fixes: [],
            improvements: []
        )
    }

    @Test("Decodes a release; fixes and improvements default to empty")
    func decodes() throws {
        let json = #"{"releases":[{"version":"1.4.0","highlights":[{"symbol":"globe","title":{"en":"T","es":"T-es"},"body":{"en":"B"}}]}]}"#
        let catalog = try WhatsNewCatalog.decode(Data(json.utf8))
        #expect(catalog.releases.count == 1)
        #expect(catalog.releases[0].highlights[0].symbol == "globe")
        #expect(catalog.releases[0].highlights[0].title.resolved(for: "es") == "T-es")
        #expect(catalog.releases[0].fixes.isEmpty)
        #expect(catalog.releases[0].improvements.isEmpty)
    }

    @Test("A release without highlights does not decode")
    func highlightsRequired() {
        let json = #"{"releases":[{"version":"1.4.0","fixes":[{"en":"F"}]}]}"#
        #expect(throws: (any Error).self) { try WhatsNewCatalog.decode(Data(json.utf8)) }
    }

    @Test("Garbage does not decode")
    func garbage() {
        #expect(throws: (any Error).self) { try WhatsNewCatalog.decode(Data("nope".utf8)) }
    }

    @Test("A bundle without the file loads an empty catalog")
    func missingFile() {
        #expect(WhatsNewCatalog.load(from: Bundle(for: BundleToken.self)) == .empty)
    }

    @Test("Resolves the language, then its base language, then English", arguments: [
        ("es", "hola"), ("pt-PT", "olá"), ("pt-BR", "olá"), ("es-419", "hola"), ("de", "hello"),
    ])
    func resolves(language: String, expected: String) {
        let text = LocalizedText(["en": "hello", "es": "hola", "pt-PT": "olá"])
        #expect(text.resolved(for: language) == expected)
    }

    @Test("No English and no match resolves to an empty string")
    func noFallback() {
        #expect(LocalizedText(["es": "hola"]).resolved(for: "de") == "")
    }

    @Test("Unknown or missing symbols fall back to sparkles")
    func symbols() {
        let text = LocalizedText(["en": "x"])
        #expect(WhatsNewHighlight(symbol: "globe", title: text, body: text).resolvedSymbol == "globe")
        #expect(WhatsNewHighlight(symbol: "not.a.symbol", title: text, body: text).resolvedSymbol == "sparkles")
        #expect(WhatsNewHighlight(symbol: nil, title: text, body: text).resolvedSymbol == "sparkles")
    }

    @Test("Range is exclusive below, inclusive above, newest first")
    func range() {
        let catalog = WhatsNewCatalog(releases: ["1.3.0", "1.5.0", "1.4.0", "1.6.0"].map { release($0) })
        #expect(catalog.releases(newerThan: "1.3.0", upTo: "1.5.0", compare: numeric).map(\.version) == ["1.5.0", "1.4.0"])
    }

    @Test("Latest with highlights skips fix-only and future releases")
    func latest() {
        let catalog = WhatsNewCatalog(releases: [
            release("1.4.0", highlights: 1),
            release("1.5.0"),
            release("1.6.0", highlights: 1),
        ])
        #expect(catalog.latestWithHighlights(upTo: "1.5.0", compare: numeric)?.version == "1.4.0")
        #expect(WhatsNewCatalog.empty.latestWithHighlights(upTo: "1.5.0", compare: numeric) == nil)
    }

    @Test("The bundled file decodes and every entry is complete")
    func bundledIsValid() throws {
        let url = try #require(Bundle.main.url(forResource: "whats-new", withExtension: "json"))
        let catalog = try WhatsNewCatalog.decode(Data(contentsOf: url))
        let versions = catalog.releases.map(\.version)
        #expect(Set(versions).count == versions.count)
        for release in catalog.releases {
            let texts = release.highlights.flatMap { [$0.title, $0.body] } + release.fixes + release.improvements
            for text in texts {
                #expect(!(text.values["en"] ?? "").isEmpty, "\(release.version): a text has no English")
            }
            for highlight in release.highlights {
                if let symbol = highlight.symbol {
                    #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil,
                            "\(release.version): unknown SF Symbol \(symbol)")
                }
            }
        }
    }
}
