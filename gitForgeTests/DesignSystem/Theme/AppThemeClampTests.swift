import Foundation
import Testing
@testable import gitForge

/// Validates the defensive clamps on the persisted-int getters. These run
/// against `UserDefaults.standard` because that's what production code reads —
/// each test saves/restores the original value so the suite doesn't pollute
/// the developer's prefs.
@Suite("AppTheme — persisted clamps", .serialized)
struct AppThemeClampTests {

    // MARK: gitTimeoutSeconds

    private static let timeoutKey = "appTheme.gitTimeout"

    private func withTimeoutOverride<T>(_ value: Any?, _ body: () -> T) -> T {
        let previous = UserDefaults.standard.object(forKey: Self.timeoutKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: Self.timeoutKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.timeoutKey)
            }
        }
        if let value {
            UserDefaults.standard.set(value, forKey: Self.timeoutKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.timeoutKey)
        }
        return body()
    }

    @Test("Git timeout default (no value persisted) is 60 seconds")
    func gitTimeoutDefault() {
        let result = withTimeoutOverride(nil) { AppTheme.persistedGitTimeoutSeconds() }
        #expect(result == 60)
    }

    @Test("Git timeout zero clamps up to 5 (watchdog would fire instantly otherwise)")
    func gitTimeoutZeroClamps() {
        let result = withTimeoutOverride(0) { AppTheme.persistedGitTimeoutSeconds() }
        #expect(result == 5)
    }

    @Test("Git timeout negative clamps up to 5")
    func gitTimeoutNegativeClamps() {
        let result = withTimeoutOverride(-100) { AppTheme.persistedGitTimeoutSeconds() }
        #expect(result == 5)
    }

    @Test("Git timeout very large clamps down to 3600")
    func gitTimeoutHugeClamps() {
        let result = withTimeoutOverride(99_999) { AppTheme.persistedGitTimeoutSeconds() }
        #expect(result == 3600)
    }

    @Test("Git timeout in-range passes through unchanged")
    func gitTimeoutInRange() {
        let result = withTimeoutOverride(120) { AppTheme.persistedGitTimeoutSeconds() }
        #expect(result == 120)
    }

    // MARK: commitPageSize

    private static let pageSizeKey = "appTheme.commitPageSize"

    private func withPageSizeOverride<T>(_ value: Any?, _ body: () -> T) -> T {
        let previous = UserDefaults.standard.object(forKey: Self.pageSizeKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: Self.pageSizeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.pageSizeKey)
            }
        }
        if let value {
            UserDefaults.standard.set(value, forKey: Self.pageSizeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pageSizeKey)
        }
        return body()
    }

    @Test("Commit page size default is 200")
    func commitPageSizeDefault() {
        let result = withPageSizeOverride(nil) { AppTheme.persistedCommitPageSize() }
        #expect(result == 200)
    }

    @Test("Commit page size zero clamps up to 50 (would otherwise load no commits)")
    func commitPageSizeZeroClamps() {
        let result = withPageSizeOverride(0) { AppTheme.persistedCommitPageSize() }
        #expect(result == 50)
    }

    @Test("Commit page size negative clamps up to 50")
    func commitPageSizeNegativeClamps() {
        let result = withPageSizeOverride(-10) { AppTheme.persistedCommitPageSize() }
        #expect(result == 50)
    }

    @Test("Commit page size very large clamps down to 5000")
    func commitPageSizeHugeClamps() {
        let result = withPageSizeOverride(1_000_000) { AppTheme.persistedCommitPageSize() }
        #expect(result == 5000)
    }

    @Test("Commit page size in-range passes through unchanged")
    func commitPageSizeInRange() {
        let result = withPageSizeOverride(500) { AppTheme.persistedCommitPageSize() }
        #expect(result == 500)
    }

    // MARK: diffContextLines

    private static let diffContextKey = "appTheme.diffContext"

    private func withDiffContextOverride<T>(_ value: Any?, _ body: () -> T) -> T {
        let previous = UserDefaults.standard.object(forKey: Self.diffContextKey)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: Self.diffContextKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.diffContextKey)
            }
        }
        if let value {
            UserDefaults.standard.set(value, forKey: Self.diffContextKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.diffContextKey)
        }
        return body()
    }

    @Test("Diff context default is 3")
    func diffContextDefault() {
        let result = withDiffContextOverride(nil) { AppTheme.persistedDiffContextLines() }
        #expect(result == 3)
    }

    @Test("Diff context negative clamps up to 0 (git -U-3 would error)")
    func diffContextNegativeClamps() {
        let result = withDiffContextOverride(-1) { AppTheme.persistedDiffContextLines() }
        #expect(result == 0)
    }

    @Test("Diff context zero is allowed (--unified=0 is valid for collapsed diffs)")
    func diffContextZeroAllowed() {
        let result = withDiffContextOverride(0) { AppTheme.persistedDiffContextLines() }
        #expect(result == 0)
    }

    @Test("Diff context very large clamps down to 100")
    func diffContextHugeClamps() {
        let result = withDiffContextOverride(99_999) { AppTheme.persistedDiffContextLines() }
        #expect(result == 100)
    }

    @Test("Diff context in-range passes through unchanged")
    func diffContextInRange() {
        let result = withDiffContextOverride(10) { AppTheme.persistedDiffContextLines() }
        #expect(result == 10)
    }
}
