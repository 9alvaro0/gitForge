import Foundation
import os

extension GitCLI {
    static func isGitAvailable(executablePath: String = "/usr/bin/env") async -> Bool {
        guard let status = await GitProcess.runTool(executablePath, arguments: ["git", "--version"]) else {
            logger.error("git availability check failed: could not launch \(executablePath, privacy: .public)")
            return false
        }
        let available = status == 0
        logger.debug("git availability check: \(available ? "found" : "missing", privacy: .public)")
        return available
    }
}
