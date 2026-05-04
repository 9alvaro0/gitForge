import Foundation

extension GitCLI {
    static func isGitRepository(at url: URL) async -> Bool {
        let path = url.path(percentEncoded: false)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        let cli = GitCLI(workingDirectory: url)
        do {
            _ = try await cli.run(["rev-parse", "--git-dir"])
            return true
        } catch {
            return false
        }
    }
}
