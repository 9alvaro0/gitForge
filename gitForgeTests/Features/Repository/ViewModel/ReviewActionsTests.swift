import Foundation
import Testing
@testable import gitForge

@Suite("Review actions")
struct ReviewActionsTests {
    static func pr(author: String?, state: PullRequest.State = .open) -> PullRequest {
        PullRequest(id: "1", number: 1, title: "T", state: state, authorLogin: author, authorAvatarURL: nil,
                    sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil)
    }

    @Test("GitHub: your own PR offers nothing; someone else's offers both; your approval shows")
    func gitHub() {
        #expect(ReviewActions.resolve(provider: .github, pull: Self.pr(author: "octo"), currentUser: "octo",
                                      reviewers: [], viewerApproval: nil, requestChanges: .supported) == .hidden)
        let other = ReviewActions.resolve(provider: .github, pull: Self.pr(author: "marta"), currentUser: "octo",
                                          reviewers: [.init(login: "octo", state: .approved)], viewerApproval: nil, requestChanges: .supported)
        #expect(other.approve == .approved)
        #expect(other.requestChanges == .available)
    }

    @Test("GitHub: someone else approving doesn't mark you as approved; an unknown user still gets both")
    func gitHubOthers() {
        let approvedByOthers = ReviewActions.resolve(provider: .github, pull: Self.pr(author: "marta"), currentUser: "octo",
                                                     reviewers: [.init(login: "luis", state: .approved)], viewerApproval: nil,
                                                     requestChanges: .supported)
        #expect(approvedByOthers.approve == .available)
        let unknownUser = ReviewActions.resolve(provider: .github, pull: Self.pr(author: "marta"), currentUser: nil,
                                                reviewers: [], viewerApproval: nil, requestChanges: nil)
        #expect(unknownUser == ReviewActions(approve: .available, requestChanges: .available))
    }

    @Test("GitLab: the host's can-approve decides; old instances explain request changes")
    func gitLab() {
        #expect(ReviewActions.resolve(provider: .gitlab, pull: Self.pr(author: "marta"), currentUser: "octo", reviewers: [],
                                      viewerApproval: .init(canApprove: false, hasApproved: false), requestChanges: .supported) == .hidden)
        let old = ReviewActions.resolve(provider: .gitlab, pull: Self.pr(author: "marta"), currentUser: "octo", reviewers: [],
                                        viewerApproval: .init(canApprove: true, hasApproved: false),
                                        requestChanges: .unsupported(reason: "Requesting changes needs GitLab 17.3 or later"))
        #expect(old.approve == .available)
        #expect(old.requestChanges == .unavailable(reason: "Requesting changes needs GitLab 17.3 or later"))
    }

    @Test("GitLab: your approval shows; support not known yet hides request changes; your own MR offers nothing")
    func gitLabStates() {
        let approved = ReviewActions.resolve(provider: .gitlab, pull: Self.pr(author: "marta"), currentUser: "octo", reviewers: [],
                                             viewerApproval: .init(canApprove: false, hasApproved: true), requestChanges: nil)
        #expect(approved == ReviewActions(approve: .approved, requestChanges: .hidden))
        #expect(ReviewActions.resolve(provider: .gitlab, pull: Self.pr(author: "octo"), currentUser: "octo", reviewers: [],
                                      viewerApproval: .init(canApprove: true, hasApproved: false), requestChanges: .supported) == .hidden)
    }

    @Test("Closed and merged PRs offer nothing")
    func closed() {
        for state in [PullRequest.State.closed, .merged] {
            #expect(ReviewActions.resolve(provider: .github, pull: Self.pr(author: "marta", state: state), currentUser: "octo",
                                          reviewers: [], viewerApproval: nil, requestChanges: .supported) == .hidden)
        }
    }
}
