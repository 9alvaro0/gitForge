import Foundation

/// Cloud-sync folders that touch their contents independently of the user.
/// `.git/index.lock`, packfiles, and ref atomic-rename dances are notorious
/// sources of corruption when a sync agent rewrites bytes mid-transaction —
/// detecting these lets us warn rather than wait for an unreproducible bug
/// report.
enum SyncedFolder: Sendable, Equatable {
    case iCloud
    case dropbox
    case oneDrive
    case googleDrive

    var displayName: String {
        switch self {
        case .iCloud:      "iCloud Drive"
        case .dropbox:     "Dropbox"
        case .oneDrive:    "OneDrive"
        case .googleDrive: "Google Drive"
        }
    }
}

enum SyncedFolderDetector {
    /// Returns the sync provider whose folder `url` lives inside, or nil for
    /// a plain local path. Match by path substring; covers the standard
    /// locations these providers use on macOS today (`~/Library/Mobile
    /// Documents/...` for iCloud, `~/Library/CloudStorage/...` for modern
    /// OneDrive/Google Drive, classic `~/Dropbox/...`).
    static func detect(in url: URL) -> SyncedFolder? {
        let path = url.path(percentEncoded: false)
        if path.contains("/Library/Mobile Documents/") {
            return .iCloud
        }
        if path.contains("/Library/CloudStorage/OneDrive") {
            return .oneDrive
        }
        if path.contains("/Library/CloudStorage/GoogleDrive") {
            return .googleDrive
        }
        // Dropbox uses ~/Dropbox by default but `~/Dropbox (Team Name)/` for
        // multi-account installs, and recently `~/Library/CloudStorage/Dropbox`
        // for the macOS-native variant.
        if path.contains("/Dropbox/")
            || path.contains("/Dropbox (")
            || path.contains("/Library/CloudStorage/Dropbox") {
            return .dropbox
        }
        return nil
    }
}
