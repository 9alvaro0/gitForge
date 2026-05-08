import Foundation
import SwiftUI
import HighlightSwift

/// Tokenises diff hunks via HighlightSwift (highlight.js + JavaScriptCore)
/// and returns per-line `AttributedString`s keyed by `DiffLine.id`. The
/// underlying `Highlight` instance is `Sendable` and runs JS off-main, so
/// callers just await results from any actor.
///
/// Strategy: a hunk's lines are joined with `\n` and tokenised as a single
/// block. This keeps multi-line strings/comments _inside_ the hunk
/// consistent. Constructs whose opening token lives in unseen file context
/// (above the hunk) degrade gracefully — highlight.js falls back to plain
/// runs.
///
/// HighlightSwift trims leading/trailing whitespace from its input before
/// rendering (see `Highlight.swift`). Hunks that start or end with empty
/// content lines would shift our offset map, so we fence the joined string
/// with non-whitespace sentinels and slice them off after.
@MainActor
final class DiffSyntaxHighlighter {
    static let shared = DiffSyntaxHighlighter()

    private let highlight = Highlight()
    private var cache: [CacheKey: [Int: AttributedString]] = [:]

    private struct CacheKey: Hashable {
        let themeId: String
        let language: String
        let contentHash: Int
    }

    /// Sentinel character that survives `trimmingCharacters(.whitespacesAndNewlines)`
    /// and renders as a plain identifier in every supported language so it
    /// doesn't perturb the highlighter's parser state.
    private static let sentinel: Character = "_"

    private init() {}

    func tokenize(
        hunk: DiffHunk,
        language: String,
        css: String,
        themeId: String
    ) async -> [Int: AttributedString] {
        let joined = hunk.lines.map(\.content).joined(separator: "\n")
        let key = CacheKey(themeId: themeId, language: language, contentHash: joined.hashValue)
        if let cached = cache[key] { return cached }

        let padded = "\(Self.sentinel)\n\(joined)\n\(Self.sentinel)"
        let attributed: AttributedString
        do {
            attributed = try await highlight.attributedText(
                padded,
                language: language,
                colors: .custom(css: css)
            )
        } catch {
            return [:]
        }

        let inner = Self.stripSentinels(attributed)
        let result = Self.split(inner, into: hunk.lines)
        cache[key] = result
        return result
    }

    // MARK: - Sentinel stripping

    /// Drops the leading `"_\n"` and trailing `"\n_"` we padded around the
    /// joined hunk content. Operates over the underlying `NSAttributedString`
    /// because `AttributedString` ranges are awkward for byte-precise slicing.
    private static func stripSentinels(_ source: AttributedString) -> NSAttributedString {
        let ns = NSAttributedString(source)
        let length = ns.length
        guard length >= 4 else { return ns }
        let inner = NSRange(location: 2, length: length - 4)
        return ns.attributedSubstring(from: inner)
    }

    /// Splits a single highlighted `NSAttributedString` (lines joined by `\n`)
    /// back into per-`DiffLine` `AttributedString`s. Newline separators are
    /// dropped — each row paints its own line independently.
    private static func split(
        _ attributed: NSAttributedString,
        into lines: [DiffLine]
    ) -> [Int: AttributedString] {
        let raw = attributed.string as NSString
        var result: [Int: AttributedString] = [:]
        var cursor = 0
        for (index, line) in lines.enumerated() {
            let length = (line.content as NSString).length
            let safeLength = max(0, min(length, raw.length - cursor))
            let range = NSRange(location: cursor, length: safeLength)
            let slice = attributed.attributedSubstring(from: range)
            result[line.id] = AttributedString(slice)
            cursor += safeLength
            if index < lines.count - 1, cursor < raw.length, raw.character(at: cursor) == 0x0A {
                cursor += 1
            }
        }
        return result
    }

    // MARK: - CSS theme

    /// Builds a highlight.js-compatible CSS sheet from the active palette.
    /// Token mappings stay conservative: keywords get accent, strings reuse
    /// the add green, comments take a muted fg3, types/functions/numbers
    /// each get a distinct palette colour so dense code stays scannable
    /// without a rainbow.
    ///
    /// Crucially the rule omits any `background` declaration: the row
    /// already has its own kind-tinted background (`addSoft`/`delSoft`/
    /// clear), and a CSS background here would round-trip through Cocoa's
    /// HTML parser as a per-run `.backgroundColor` attribute, painting a
    /// rectangle behind every glyph and obliterating the row tint.
    static func css(for p: ThemePalette) -> String {
        let accent = p.accent.cssHex
        let add = p.add.cssHex
        let del = p.del.cssHex
        let info = p.info.cssHex
        let mod = p.mod.cssHex
        let muted = p.fg3.cssHex
        return """
        .hljs-keyword,
        .hljs-selector-tag,
        .hljs-built_in,
        .hljs-literal,
        .hljs-section,
        .hljs-meta,
        .hljs-meta-keyword { color: \(accent); }
        .hljs-string,
        .hljs-template-string,
        .hljs-regexp,
        .hljs-attr-string,
        .hljs-symbol,
        .hljs-bullet,
        .hljs-link { color: \(add); }
        .hljs-comment,
        .hljs-quote,
        .hljs-doctag,
        .hljs-meta .hljs-keyword { color: \(muted); font-style: italic; }
        .hljs-number,
        .hljs-formula { color: \(mod); }
        .hljs-type,
        .hljs-class .hljs-title,
        .hljs-title.class_,
        .hljs-tag,
        .hljs-name,
        .hljs-selector-id,
        .hljs-selector-class { color: \(info); }
        .hljs-function .hljs-title,
        .hljs-title.function_,
        .hljs-property,
        .hljs-attr,
        .hljs-attribute { color: \(mod); }
        .hljs-deletion { color: \(del); }
        .hljs-addition { color: \(add); }
        .hljs-emphasis { font-style: italic; }
        .hljs-strong { font-weight: bold; }
        """
    }

    // MARK: - Language detection

    /// Maps a file path to a highlight.js language alias. Returns `nil` for
    /// unknown extensions / extensionless paths — callers fall back to
    /// plain text rendering.
    static func languageId(for path: String?) -> String? {
        guard let path, !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty, let lang = extensionMap[ext] { return lang }
        let base = url.lastPathComponent.lowercased()
        return basenameMap[base]
    }

    private static let extensionMap: [String: String] = [
        "swift": "swift",
        "ts": "typescript", "tsx": "typescript",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
        "json": "json",
        "py": "python",
        "rb": "ruby",
        "go": "go",
        "rs": "rust",
        "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "m": "objectivec",
        "mm": "objectivec",
        "h": "cpp", "hpp": "cpp",
        "c": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp",
        "cs": "csharp",
        "php": "php",
        "scala": "scala",
        "sh": "bash", "bash": "bash", "zsh": "bash", "fish": "bash",
        "yaml": "yaml", "yml": "yaml",
        "toml": "ini",
        "xml": "xml", "plist": "xml",
        "html": "xml", "htm": "xml",
        "css": "css", "scss": "scss", "sass": "scss", "less": "less",
        "md": "markdown", "markdown": "markdown",
        "sql": "sql",
        "lua": "lua",
        "pl": "perl",
        "r": "r",
        "dart": "dart",
        "ex": "elixir", "exs": "elixir",
        "elm": "elm",
        "fs": "fsharp", "fsx": "fsharp",
        "hs": "haskell",
        "clj": "clojure", "cljs": "clojure",
        "ml": "ocaml",
        "tex": "latex",
        "vim": "vim",
        "diff": "diff", "patch": "diff",
        "ini": "ini",
        "env": "bash",
        "graphql": "graphql", "gql": "graphql",
        "proto": "protobuf",
        "tf": "hcl", "hcl": "hcl",
        "dockerfile": "dockerfile",
        "makefile": "makefile",
    ]

    private static let basenameMap: [String: String] = [
        "dockerfile": "dockerfile",
        "makefile": "makefile",
        "gnumakefile": "makefile",
        "cmakelists.txt": "cmake",
        "podfile": "ruby",
        "gemfile": "ruby",
        "rakefile": "ruby",
        "package.json": "json",
        "tsconfig.json": "json",
        ".gitignore": "bash",
        ".gitattributes": "bash",
        ".env": "bash",
    ]
}
