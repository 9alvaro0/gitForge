import Foundation

extension GitCLI {
    /// `git blame --porcelain <file>` output, ready to feed `BlameParser`.
    func blame(path: String) async throws -> String {
        let result = try await run(["blame", "--porcelain", "--", path])
        return result.stdout
    }
}
