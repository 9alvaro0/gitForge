import Foundation
import Testing
@testable import gitForge

@Suite("SidebarHost.identityDiff")
@MainActor
struct SidebarHostIdentityDiffTests {

    private func profile(
        name: String = "Personal",
        userName: String = "Alvaro",
        userEmail: String = "alvaro@example.com",
        signingKey: String? = nil
    ) -> GitProfile {
        GitProfile(name: name, userName: userName, userEmail: userEmail, signingKey: signingKey)
    }

    @Test("Returns nil when name/email/signing key all match")
    func returnsNilWhenIdentical() {
        let current = RepoIdentity(name: "Alvaro", email: "alvaro@example.com", signingKey: nil, isLocal: false)
        let next = profile()
        #expect(SidebarHost.identityDiff(from: current, to: next) == nil)
    }

    @Test("Whitespace differences are ignored")
    func ignoresWhitespace() {
        let current = RepoIdentity(name: "  Alvaro  ", email: "alvaro@example.com\n", signingKey: nil, isLocal: false)
        let next = profile()
        #expect(SidebarHost.identityDiff(from: current, to: next) == nil)
    }

    @Test("Reports email diff when only email changes")
    func reportsEmailChange() {
        let current = RepoIdentity(name: "Alvaro", email: "old@example.com", signingKey: nil, isLocal: false)
        let next = profile(userEmail: "new@example.com")
        let diff = SidebarHost.identityDiff(from: current, to: next)
        #expect(diff != nil)
        #expect(diff?.message.contains("Email:") == true)
        #expect(diff?.message.contains("old@example.com") == true)
        #expect(diff?.message.contains("new@example.com") == true)
        // Name and signing key shouldn't show up as changes.
        #expect(diff?.message.contains("Name:") == false)
        #expect(diff?.message.contains("Signing key:") == false)
    }

    @Test("Flags explicit warning when signing key is being removed")
    func warnsOnSigningKeyRemoval() {
        let current = RepoIdentity(name: "Alvaro", email: "alvaro@example.com", signingKey: "ABC123", isLocal: true)
        let next = profile(signingKey: nil)
        let diff = SidebarHost.identityDiff(from: current, to: next)
        #expect(diff != nil)
        #expect(diff?.message.contains("Signing key: will be removed") == true)
        #expect(diff?.message.contains("won’t be GPG-signed") == true)
    }

    @Test("Setting a signing key on a repo that had none renders as 'will be set'")
    func reportsSigningKeyAddition() {
        let current = RepoIdentity(name: "Alvaro", email: "alvaro@example.com", signingKey: nil, isLocal: false)
        let next = profile(signingKey: "ABC123")
        let diff = SidebarHost.identityDiff(from: current, to: next)
        #expect(diff?.message.contains("Signing key: will be set to ABC123") == true)
    }

    @Test("Swap of signing key reports old → new")
    func reportsSigningKeySwap() {
        let current = RepoIdentity(name: "Alvaro", email: "alvaro@example.com", signingKey: "OLD", isLocal: true)
        let next = profile(signingKey: "NEW")
        let diff = SidebarHost.identityDiff(from: current, to: next)
        #expect(diff?.message.contains("Signing key: OLD → NEW") == true)
    }

    @Test("Nil current identity (fresh repo) still produces a diff")
    func handlesNilCurrent() {
        let diff = SidebarHost.identityDiff(from: nil, to: profile())
        #expect(diff != nil)
        #expect(diff?.message.contains("Name:") == true)
        #expect(diff?.message.contains("Email:") == true)
    }

    @Test("Header always names .git/config so the user knows where the write lands")
    func headerMentionsGitConfig() {
        let current = RepoIdentity(name: "X", email: "y", signingKey: nil, isLocal: false)
        let next = profile()
        let diff = SidebarHost.identityDiff(from: current, to: next)
        #expect(diff?.message.contains(".git/config") == true)
    }
}
