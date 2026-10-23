import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// The pull request detail's header keeps to the column it's given.
@Suite("Pull request detail header")
@MainActor
struct PullRequestDetailHeaderTests {
    static let longBranch = "feature/a-very-long-branch-name-that-keeps-going-past-the-header-width-on-purpose"

    static func header(source: String, target: String = "develop") -> some View {
        PullRequestDetailHeader(
            pullRequest: PullRequest(id: "41", number: 41, title: "Keep the header inside its column", state: .open,
                                     authorLogin: "marta", authorAvatarURL: nil, sourceBranch: source,
                                     targetBranch: target, webURL: nil, createdAt: nil, updatedAt: nil),
            hostLabel: "GitLab",
            reference: "!41",
            repositoryLabel: "acme/apps/storefront",
            commitCount: 3,
            reviewers: [],
            labels: [],
            leading: .button(title: "Clone repository…", systemImage: "square.and.arrow.down", action: {})
        )
        .appTheme(AppTheme())
    }

    private static func width(of view: some View, offered width: CGFloat) -> CGFloat {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 2_000)).width
    }

    @Test("A branch name longer than the column is cut, source or target, and the header stays within its width",
          arguments: [520, 320] as [CGFloat])
    func longBranchFits(width: CGFloat) {
        #expect(Self.width(of: Self.header(source: Self.longBranch), offered: width) <= width)
        #expect(Self.width(of: Self.header(source: "fix/x", target: Self.longBranch), offered: width) <= width)
    }
}
