import AppKit
import Foundation

/// Orders two marketing versions ("1.4.0", "1.10.0-beta.1").
typealias WhatsNewVersionCompare = @Sendable (String, String) -> ComparisonResult

/// A text written once per language (`en`, `es`, `pt-PT`). Decodes from a
/// JSON object keyed by language code.
nonisolated struct LocalizedText: Equatable, Sendable {
    var values: [String: String]

    init(_ values: [String: String]) {
        self.values = values
    }

    /// The text in `language`, else in another variant of the same base
    /// language (`pt-BR` → `pt-PT`), else in English, else empty.
    func resolved(for language: String) -> String {
        if let exact = values[language] { return exact }
        let base = Self.baseLanguage(language)
        if let sibling = values.keys.sorted().first(where: { Self.baseLanguage($0) == base }),
           let text = values[sibling] {
            return text
        }
        return values["en"] ?? ""
    }

    private static func baseLanguage(_ code: String) -> Substring {
        code.split(separator: "-", maxSplits: 1).first ?? Substring(code)
    }
}

extension LocalizedText: Decodable {
    nonisolated init(from decoder: any Decoder) throws {
        values = try decoder.singleValueContainer().decode([String: String].self)
    }
}

/// One new feature: an SF Symbol, a short title and one sentence.
nonisolated struct WhatsNewHighlight: Decodable, Equatable, Sendable {
    static let defaultSymbol = "sparkles"

    var symbol: String?
    var title: LocalizedText
    var body: LocalizedText

    /// `symbol` when this macOS knows it, else `defaultSymbol`.
    var resolvedSymbol: String {
        guard let symbol, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil else {
            return Self.defaultSymbol
        }
        return symbol
    }
}

/// The notes of one published version. A release without highlights only
/// brings fixes or improvements and never raises the sheet.
nonisolated struct WhatsNewRelease: Equatable, Sendable, Identifiable {
    var version: String
    var highlights: [WhatsNewHighlight]
    var fixes: [LocalizedText]
    var improvements: [LocalizedText]

    var id: String { version }
}

extension WhatsNewRelease: Decodable {
    private nonisolated enum CodingKeys: String, CodingKey {
        case version, highlights, fixes, improvements
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        highlights = try container.decode([WhatsNewHighlight].self, forKey: .highlights)
        fixes = try container.decodeIfPresent([LocalizedText].self, forKey: .fixes) ?? []
        improvements = try container.decodeIfPresent([LocalizedText].self, forKey: .improvements) ?? []
    }
}

/// Every release's notes, read from `whats-new.json` in the app bundle.
/// The same file feeds the release notes `ship.sh` publishes.
nonisolated struct WhatsNewCatalog: Decodable, Equatable, Sendable {
    static let fileName = "whats-new"
    static let empty = WhatsNewCatalog(releases: [])
    /// Read once from the app bundle.
    static let bundled = load()

    var releases: [WhatsNewRelease]

    static func decode(_ data: Data) throws -> WhatsNewCatalog {
        try JSONDecoder().decode(WhatsNewCatalog.self, from: data)
    }

    /// The catalog in `bundle`, or `.empty` when the file is missing. A file
    /// that is there but unreadable is a build mistake: it trips an
    /// assertion in debug and shows nothing in release.
    static func load(from bundle: Bundle = .main) -> WhatsNewCatalog {
        guard let url = bundle.url(forResource: fileName, withExtension: "json") else { return .empty }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            assertionFailure("Unreadable \(fileName).json: \(error)")
            return .empty
        }
    }

    /// The language the app runs in, which follows Settings › Language.
    static func preferredLanguage(bundle: Bundle = .main) -> String {
        bundle.preferredLocalizations.first ?? "en"
    }

    /// Releases with `lower < version ≤ upper`, newest first.
    func releases(newerThan lower: String, upTo upper: String,
                  compare: WhatsNewVersionCompare) -> [WhatsNewRelease] {
        releases
            .filter { compare($0.version, lower) == .orderedDescending && compare($0.version, upper) != .orderedDescending }
            .sorted { compare($0.version, $1.version) == .orderedDescending }
    }

    /// The newest release up to `upper` that has highlights.
    func latestWithHighlights(upTo upper: String, compare: WhatsNewVersionCompare) -> WhatsNewRelease? {
        releases
            .filter { !$0.highlights.isEmpty && compare($0.version, upper) != .orderedDescending }
            .max { compare($0.version, $1.version) == .orderedAscending }
    }
}
