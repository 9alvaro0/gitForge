import Foundation
import os

extension GitCLI {
    static func isGitAvailable(executablePath: String = "/usr/bin/env") async -> Bool {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = ["git", "--version"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let available = process.terminationStatus == 0
                logger.debug("git availability check: \(available ? "found" : "missing", privacy: .public)")
                return available
            } catch {
                logger.error("git availability check failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }.value
    }
}
