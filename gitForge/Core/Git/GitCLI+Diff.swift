import Foundation

extension GitCLI {
    func diffUnstaged(file: String) async throws -> String {
        try await run(["diff", "--", file]).stdout
    }

    func diffStaged(file: String) async throws -> String {
        try await run(["diff", "--cached", "--", file]).stdout
    }
}
