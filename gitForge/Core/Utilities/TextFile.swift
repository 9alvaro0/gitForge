import Foundation

/// Reads and writes text files without losing bytes the app doesn't
/// understand. Used by the conflict resolver, which rewrites files in place.
///
/// UTF-8 is tried first; anything else is decoded as ISO Latin-1, which maps
/// every byte 1:1 to a code point. Writing back with the same encoding
/// therefore reproduces the original bytes exactly — including the ones
/// that weren't valid UTF-8 (Latin-1 / Windows-1252 legacy sources), which
/// the previous UTF-8-only path either refused to open or would have
/// rewritten as U+FFFD. Conflict markers are ASCII, so parsing works the
/// same under both encodings.
nonisolated enum TextFile {
    struct Contents: Sendable {
        let text: String
        let encoding: String.Encoding
    }

    static func read(_ url: URL) throws -> Contents {
        let data = try Data(contentsOf: url)
        if let text = String(data: data, encoding: .utf8) {
            return Contents(text: text, encoding: .utf8)
        }
        // Latin-1 decoding never fails: every byte is a valid code point.
        return Contents(text: String(data: data, encoding: .isoLatin1) ?? "", encoding: .isoLatin1)
    }

    static func write(_ text: String, encoding: String.Encoding, to url: URL) throws {
        guard let data = text.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try data.write(to: url, options: .atomic)
    }
}
