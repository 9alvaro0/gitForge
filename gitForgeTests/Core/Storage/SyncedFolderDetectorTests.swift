import Foundation
import Testing
@testable import gitForge

@Suite("SyncedFolderDetector")
struct SyncedFolderDetectorTests {

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    @Test("Plain path under /Users returns nil")
    func plainPath() {
        #expect(SyncedFolderDetector.detect(in: url("/Users/me/code/repo")) == nil)
    }

    @Test("iCloud Drive path (Mobile Documents) detected")
    func detectsICloud() {
        let u = url("/Users/me/Library/Mobile Documents/com~apple~CloudDocs/repo")
        #expect(SyncedFolderDetector.detect(in: u) == .iCloud)
    }

    @Test("Classic ~/Dropbox path detected")
    func detectsClassicDropbox() {
        #expect(SyncedFolderDetector.detect(in: url("/Users/me/Dropbox/work/repo")) == .dropbox)
    }

    @Test("Dropbox business path with parenthesised suffix detected")
    func detectsDropboxBusiness() {
        let u = url("/Users/me/Dropbox (Mercadona)/repo")
        #expect(SyncedFolderDetector.detect(in: u) == .dropbox)
    }

    @Test("Modern Dropbox under CloudStorage detected")
    func detectsCloudStorageDropbox() {
        let u = url("/Users/me/Library/CloudStorage/Dropbox/repo")
        #expect(SyncedFolderDetector.detect(in: u) == .dropbox)
    }

    @Test("OneDrive under CloudStorage detected")
    func detectsOneDrive() {
        let u = url("/Users/me/Library/CloudStorage/OneDrive-Personal/repo")
        #expect(SyncedFolderDetector.detect(in: u) == .oneDrive)
    }

    @Test("Google Drive under CloudStorage detected")
    func detectsGoogleDrive() {
        let u = url("/Users/me/Library/CloudStorage/GoogleDrive-me@gmail.com/My Drive/repo")
        #expect(SyncedFolderDetector.detect(in: u) == .googleDrive)
    }

    @Test("Paths that mention 'Dropbox' in a filename, not a folder, do NOT match")
    func dropboxFalsePositive() {
        // 'Dropbox' as filename → no surrounding slashes → must not match.
        let u = url("/Users/me/notes/Dropbox.md")
        #expect(SyncedFolderDetector.detect(in: u) == nil)
    }

    @Test("Each provider has a non-empty user-facing display name")
    func displayNamesArePopulated() {
        for provider: SyncedFolder in [.iCloud, .dropbox, .oneDrive, .googleDrive] {
            #expect(provider.displayName.isEmpty == false)
        }
    }
}
