import AppKit
import os

/// The only way the app opens things outside itself. URLs that come from
/// remote data (PR descriptions, CI `target_url`s anyone with status access
/// can set, API `html_url`s) are restricted to web and mail links:
/// `NSWorkspace.open` would otherwise happily launch `file://` apps or any
/// custom URL scheme handler installed on the machine.
///
/// Files from a repository are opened in their default app, except bundles
/// and launchable types (an `.app`, a `.command` Terminal runs on open…),
/// which are revealed in Finder instead — a repo can contain anything, and
/// "Open" shouldn't mean "execute".
nonisolated enum ExternalURL {
    private static let logger = Logger(subsystem: "com.warwarelabs.gitForge", category: "external-url")

    static let allowedSchemes: Set<String> = ["http", "https", "mailto"]

    /// Extensions that run something when opened.
    static let launchableExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "workflow", "action",
        "pkg", "mpkg", "prefpane", "saver", "webloc", "inetloc", "fileloc",
    ]

    static func isSafeWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(scheme)
    }

    /// Opens a link that came from remote data. Refuses anything that isn't
    /// http(s) or mailto.
    @MainActor
    static func open(_ url: URL) {
        guard isSafeWebURL(url) else {
            logger.error("Refused to open non-web URL with scheme \(url.scheme ?? "nil", privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Whether opening this file would launch something instead of showing it.
    static func isLaunchable(_ fileURL: URL) -> Bool {
        if launchableExtensions.contains(fileURL.pathExtension.lowercased()) { return true }
        let values = try? fileURL.resourceValues(forKeys: [.isApplicationKey, .isPackageKey])
        return values?.isApplication == true || values?.isPackage == true
    }

    /// Opens a repository file in its default app, or reveals it in Finder
    /// when opening would launch it.
    @MainActor
    static func openFile(_ fileURL: URL) {
        if isLaunchable(fileURL) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.open(fileURL)
        }
    }
}
