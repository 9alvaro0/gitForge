import Foundation
import Testing
@testable import gitForge

/// What "New Profile…" (⌘K) does to the editor that is already open: it
/// never discards what the user has typed.
@Suite("ProfileDraft — New Profile request")
@MainActor
struct ProfileDraftTests {
    private static let profile = GitProfile(name: "Work", userName: "Ada Lovelace", userEmail: "ada@example.test",
                                            signingKey: "ABC123")

    @Test("With no editor open, a request opens an empty draft for a new profile")
    func opensNew() {
        let draft = ProfileDraft.requested(over: nil)
        #expect(draft.isNew)
        #expect(draft.name.isEmpty && draft.userName.isEmpty && draft.userEmail.isEmpty && draft.signingKey.isEmpty)
    }

    @Test("With the editor of an existing profile open, a request keeps that edit, unsaved changes included")
    func keepsEditOfExisting() {
        var editing = ProfileDraft(Self.profile)
        editing.userEmail = "ada@example.test.changed"
        let kept = ProfileDraft.requested(over: editing)
        #expect(kept == editing)
        #expect(!kept.isNew)
        #expect(kept.id == Self.profile.id)
    }

    @Test("With a new draft already open, a request keeps what was typed in it")
    func keepsNewDraft() {
        var typing = ProfileDraft.new()
        typing.name = "Client"
        typing.userName = "Ada"
        #expect(ProfileDraft.requested(over: typing) == typing)
    }
}
