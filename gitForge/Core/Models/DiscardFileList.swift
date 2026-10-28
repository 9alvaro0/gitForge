import Foundation

/// The files a "discard and retry" question names: one path per line, the
/// rest only counted. Shared by the pull and checkout questions.
nonisolated enum DiscardFileList {
    /// Files named; the rest are only counted.
    static let limit = 10

    static func lines(_ files: [WorkingCopyFile]) -> [String] {
        var lines = files.prefix(limit).map(\.path)
        let rest = files.count - limit
        if rest > 0 { lines.append(String(localized: "…and \(rest) more")) }
        return lines
    }
}
