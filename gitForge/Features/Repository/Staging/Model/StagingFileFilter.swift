import Foundation

/// The Changes "Filter files" field: keeps the files whose path (or, for a
/// rename, original path) contains the query, ignoring case and diacritics.
nonisolated enum StagingFileFilter {
    static func apply(_ files: [WorkingCopyFile], query: String) -> [WorkingCopyFile] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return files }
        return files.filter { file in
            file.path.localizedStandardContains(trimmed)
                || (file.originalPath?.localizedStandardContains(trimmed) ?? false)
        }
    }
}
