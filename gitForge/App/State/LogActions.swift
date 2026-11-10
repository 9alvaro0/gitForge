import AppKit
import UniformTypeIdentifiers

/// Help › Export Logs… and Help › Open Log Folder (issue #1). The report is
/// built and written off the main actor; only the save panel and the toast
/// run on it.
@MainActor
enum LogActions {
    /// Asks where to save, then writes `LogExport.report` there. Nothing is
    /// sent anywhere: the user picks the file and decides who gets it.
    static func exportLogs(ui: WorkspaceUI, log: AppLog = .shared) async {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Logs")
        panel.message = String(localized: "The file lists the errors gitForge showed and the git commands that failed, with the app, macOS and git versions. Tokens, passwords and the user name in your paths are removed. Nothing is sent: share the file only if you want to.")
        panel.prompt = String(localized: "Export")
        panel.nameFieldStringValue = LogExport.suggestedFileName(for: Date())
        panel.allowedContentTypes = [UTType.log, .plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        let gitVersion = await Self.gitVersion()
        let environment = LogExport.currentEnvironment(gitVersion: gitVersion)
        let written: Result<Void, Error> = await GitProcess.offPool {
            Result {
                let report = LogExport.report(environment: environment, logFiles: log.flushedFilesOldestFirst())
                try Data(report.utf8).write(to: destination, options: .atomic)
            }
        }
        switch written {
        case .success:
            ui.activeToast = ToastMessage(message: String(localized: "Logs exported."), kind: .ok)
        case .failure(let error):
            ui.activeToast = ToastMessage(
                message: String(localized: "Couldn’t export the logs: \(error.localizedDescription)"),
                kind: .error)
        }
    }

    /// Shows the log folder in Finder, with the current log selected when
    /// there is one. Creates the folder first so Finder always has
    /// something to open.
    static func openLogFolder(log: AppLog = .shared) {
        let directory = log.directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        if FileManager.default.fileExists(atPath: log.currentFileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log.currentFileURL])
        } else {
            NSWorkspace.shared.open(directory)
        }
    }

    /// `git version 2.50.1 (Apple Git-155)`, or why it couldn't be read.
    private static func gitVersion() async -> String {
        let cli = GitCLI(workingDirectory: FileManager.default.homeDirectoryForCurrentUser)
        do {
            let output = try await cli.run(["--version"]).stdout
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? "unknown" : output
        } catch {
            return "unavailable (\(error.localizedDescription))"
        }
    }
}
