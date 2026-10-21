import Foundation
import Testing
@testable import gitForge

@Suite("Merge draft")
struct MergeDraftTests {
    static let github = MergeOptions(kind: .github(methods: [.squash, .merge, .rebase]), canDeleteSourceBranch: true,
                                     defaultsByMethod: [.squash: [.title: "Add retry (#42)"], .merge: [.title: "Add retry (#42)", .body: "Retries failed syncs."]],
                                     initialMethod: .squash, initialSquash: false)

    @Test("Squash and delete come pre-selected; untouched messages don't travel")
    func defaults() {
        let draft = MergeDraft(options: Self.github)
        #expect(draft.method == .squash)
        #expect(draft.deleteSourceBranch)
        #expect(draft.text(for: .title, options: Self.github) == "Add retry (#42)")
        #expect(draft.text(for: .body, options: Self.github) == "")
        let input = draft.input(options: Self.github, headSha: "abc")
        #expect(input.messages.isEmpty)
        #expect(input.headSha == "abc")
        #expect(input.method == .squash)
        #expect(input.deleteSourceBranch)
    }

    @Test("Switching method swaps the untouched defaults")
    func switchMethod() {
        var draft = MergeDraft(options: Self.github)
        draft.method = .merge
        #expect(draft.text(for: .body, options: Self.github) == "Retries failed syncs.")
    }

    @Test("Edited fields travel only while the method shows them")
    func edited() {
        var draft = MergeDraft(options: Self.github)
        draft.setText("Retry policy", for: .title)
        #expect(draft.text(for: .title, options: Self.github) == "Retry policy")
        #expect(draft.input(options: Self.github, headSha: "abc").messages == [.title: "Retry policy"])
        draft.method = .rebase
        #expect(draft.input(options: Self.github, headSha: "abc").messages.isEmpty)
    }

    @Test("An emptied field with no known default is the host's default: nothing travels")
    func clearedUnknownDefault() {
        var draft = MergeDraft(options: Self.github)
        draft.setText("Why", for: .body)
        draft.setText("", for: .body)
        #expect(draft.input(options: Self.github, headSha: nil).messages.isEmpty)
    }

    @Test("Text equal to the host's default doesn't travel")
    func sameAsDefault() {
        var draft = MergeDraft(options: Self.github)
        draft.setText("Add retry (#42)", for: .title)
        #expect(draft.input(options: Self.github, headSha: nil).messages.isEmpty)
    }

    @Test("Clearing a default the sheet showed sends a blank message")
    func clearedKnownDefault() {
        var draft = MergeDraft(options: Self.github)
        draft.method = .merge
        draft.setText("", for: .body)
        #expect(draft.input(options: Self.github, headSha: nil).messages == [.body: ""])
    }

    @Test("A fork never deletes, whatever the draft says")
    func fork() {
        let fork = MergeOptions(kind: .github(methods: [.squash]), canDeleteSourceBranch: false, initialMethod: .squash, initialSquash: false)
        var draft = MergeDraft(options: fork)
        #expect(draft.deleteSourceBranch == false)
        draft.deleteSourceBranch = true
        #expect(draft.input(options: fork, headSha: nil).deleteSourceBranch == false)
    }

    @Test("Unticking delete keeps the branch")
    func keepBranch() {
        var draft = MergeDraft(options: Self.github)
        draft.deleteSourceBranch = false
        #expect(draft.input(options: Self.github, headSha: nil).deleteSourceBranch == false)
    }

    @Test("GitHub fields and confirm titles per method", arguments: [
        (MergeMethod.squash, [MergeMessageField.title, .body], "Squash and merge"),
        (.merge, [.title, .body], "Create merge commit"),
        (.rebase, [], "Rebase and merge"),
    ])
    func gitHubPerMethod(method: MergeMethod, fields: [MergeMessageField], title: String) {
        #expect(Self.github.messageFields(method: method, squash: false) == fields)
        #expect(Self.github.confirmTitle(method: method, squash: false) == title)
        #expect(!Self.github.showsSquashToggle)
    }

    @Test("GitLab fields per project method and squash", arguments: [
        (GitLabMergeMethod.merge, false, [MergeMessageField.mergeMessage]),
        (.merge, true, [.squashMessage, .mergeMessage]),
        (.rebaseMerge, false, [.mergeMessage]),
        (.rebaseMerge, true, [.squashMessage, .mergeMessage]),
        (.fastForward, true, [.squashMessage]),
        (.fastForward, false, []),
    ])
    func gitLabFields(method: GitLabMergeMethod, squash: Bool, expected: [MergeMessageField]) {
        let options = MergeOptions(kind: .gitlab(method: method, squash: .defaultOff), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: true)
        #expect(options.messageFields(method: nil, squash: squash) == expected)
    }

    @Test("Confirm titles and GitLab squash policy")
    func titlesAndPolicy() {
        #expect(Self.github.confirmTitle(method: .merge, squash: false) == "Create merge commit")
        let always = MergeOptions(kind: .gitlab(method: .merge, squash: .always), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: true)
        #expect(always.squashLocked && always.showsSquashToggle)
        #expect(always.confirmTitle(method: nil, squash: true) == "Squash and merge")
        #expect(always.confirmTitle(method: nil, squash: false) == "Merge")
        let never = MergeOptions(kind: .gitlab(method: .merge, squash: .never), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: false)
        #expect(!never.showsSquashToggle && !never.squashLocked)
        let optional = MergeOptions(kind: .gitlab(method: .merge, squash: .defaultOff), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: true)
        #expect(optional.showsSquashToggle && !optional.squashLocked)
    }

    @Test("GitLab's project policy wins over the draft's squash")
    func gitLabSquashPolicy() {
        let always = MergeOptions(kind: .gitlab(method: .merge, squash: .always), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: true)
        var draft = MergeDraft(options: always)
        draft.squash = false
        #expect(draft.input(options: always, headSha: nil).squash)
        let never = MergeOptions(kind: .gitlab(method: .merge, squash: .never), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: false)
        var neverDraft = MergeDraft(options: never)
        neverDraft.squash = true
        neverDraft.setText("Squashed", for: .squashMessage)
        let input = neverDraft.input(options: never, headSha: nil)
        #expect(!input.squash)
        #expect(input.messages.isEmpty)
    }

    @Test("GitLab: a squash message travels only while squashing")
    func gitLabSquashMessage() {
        let options = MergeOptions(kind: .gitlab(method: .fastForward, squash: .defaultOn), canDeleteSourceBranch: true, initialMethod: nil, initialSquash: true)
        var draft = MergeDraft(options: options)
        #expect(draft.squash)
        draft.setText("Squashed", for: .squashMessage)
        #expect(draft.input(options: options, headSha: nil).messages == [.squashMessage: "Squashed"])
        draft.squash = false
        #expect(draft.input(options: options, headSha: nil).messages.isEmpty)
    }
}
