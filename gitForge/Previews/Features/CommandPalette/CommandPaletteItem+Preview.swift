import Foundation

extension CommandPaletteItem {
    /// Repositories, branches, commits and files, three pull requests of the
    /// Reviews preview world and one followed repo that isn't cloned. Paste
    /// `https://gitlab.example.test/apps/payments/android/payments-app/-/merge_requests/482`
    /// to see the row that opens a link, or the same on `code.example.test`
    /// for the one that adds its host (`previewInstances`).
    @MainActor
    static var previewSamples: [CommandPaletteItem] {
        CommandPaletteBuilder.build(
            repositories: Repository.previewSamples,
            branches: GitRef.previewSamples,
            commits: Commit.previewSamples,
            workingFiles: WorkingCopyStatus.preview.files,
            pulls: previewPulls,
            unclonedRepos: previewUnclonedRepos
        )
    }

    /// What a pasted link is read against: github.com, gitlab.com and the
    /// fake `gitlab.example.test` of the Reviews previews.
    static var previewInstances: [HostingInstance] {
        HostingInstance.builtIns + [PreviewReviewsWorld.gitLab]
    }

    /// The Search all group for `query`, one instance in each state: type
    /// `retry` to see what gitlab.example.test found (a merge request, then
    /// payments-app, followed, and ledger), github.com searching, a failure on
    /// ghe.example.test, code.example.test asking for an account and nothing
    /// found on gitlab.com. Any other text of 3 characters or more gives the
    /// row that searches each of them.
    static func previewSearchItems(_ query: String) -> [CommandPaletteItem] {
        CommandPaletteBuilder.searchItems(for: query, instances: previewSearchInstances, searches: previewSearches,
                                          followed: [FollowedRepos.key(previewFoundRepo(PreviewReviewsWorld.paymentsApp).host)])
    }

    private static let previewEnterprise = HostingInstance(kind: .github, host: "ghe.example.test")
    private static let previewSelfManaged = HostingInstance(kind: .gitlab, host: "code.example.test")

    private static var previewSearchInstances: [HostingInstance] {
        [PreviewReviewsWorld.gitLab, PreviewReviewsWorld.gitHub, previewEnterprise, previewSelfManaged,
         .gitLabDotCom]
    }

    private static var previewSearches: [UUID: HostSearchState] {
        let link = PullRequestLink.parse(
            "https://gitlab.example.test/\(PreviewReviewsWorld.paymentsApp)/-/merge_requests/482",
            instances: [PreviewReviewsWorld.gitLab])
        let pulls = link.map {
            [FoundPull(link: $0, title: "Retry card authorisation after a gateway timeout", authorLogin: "marta",
                       updatedAt: nil, isDraft: false)]
        } ?? []
        let repos = [previewFoundRepo(PreviewReviewsWorld.paymentsApp), previewFoundRepo(PreviewReviewsWorld.ledger)]
        return [
            PreviewReviewsWorld.gitLab.id: HostSearchState(query: "retry",
                                                           phase: .found(HostSearchResults(pulls: pulls, repos: repos))),
            PreviewReviewsWorld.gitHub.id: HostSearchState(query: "retry", phase: .searching),
            previewEnterprise.id: HostSearchState(query: "retry", phase: .failed("The server answered 502.")),
            previewSelfManaged.id: HostSearchState(query: "retry", phase: .connectAccount),
            HostingInstance.gitLabDotCom.id: HostSearchState(query: "retry", phase: .found(HostSearchResults())),
        ]
    }

    private static func previewFoundRepo(_ path: String) -> FoundRepo {
        FoundRepo(host: RemoteHost.make(fullName: path, on: PreviewReviewsWorld.gitLab)!,
                  instanceId: PreviewReviewsWorld.gitLab.id, cloneURL: "https://gitlab.example.test/\(path).git")
    }

    /// Newest first, as ⌘K gets them; those of payments-app are in a repo with a clone.
    static var previewPulls: [InboxPull] {
        let clone = URL(fileURLWithPath: "/Users/preview/Developer/payments-app")
        let app = previewRepo(PreviewReviewsWorld.paymentsApp, localURL: clone)
        let ledger = previewRepo(PreviewReviewsWorld.ledger)
        return [
            InboxPull(repo: app, pull: previewPull(482, "Retry card authorisation after a gateway timeout",
                                                   by: "lucia", named: "Lucia Ortega", from: "fix/card-auth-gateway-timeout-retry")),
            InboxPull(repo: ledger, pull: previewPull(1203, "Round half-even in the monthly statement",
                                                      by: "pablo", named: "Pablo Serra", from: "fix/statement-rounding")),
            InboxPull(repo: app, pull: previewPull(470, "Show the refund reason on the receipt",
                                                   by: "marta", named: "Marta Ruiz", from: "feat/refund-reason")),
        ]
    }

    /// The followed repo with no clone on this Mac.
    static var previewUnclonedRepos: [ReviewRepo] {
        [previewRepo(PreviewReviewsWorld.ledger)]
    }

    private static func previewRepo(_ path: String, localURL: URL? = nil) -> ReviewRepo {
        ReviewRepo(host: RemoteHost.make(fullName: path, on: PreviewReviewsWorld.gitLab)!,
                   accountId: PreviewReviewsWorld.marta.id, sources: [], lastActivity: nil,
                   cloneURL: "https://gitlab.example.test/\(path).git", localURL: localURL)
    }

    private static func previewPull(_ number: Int, _ title: String, by login: String, named name: String,
                                    from branch: String) -> PullRequest {
        PullRequest(id: "iid:\(number)", number: number, title: title, state: .open, authorLogin: login,
                    authorAvatarURL: nil, sourceBranch: branch, targetBranch: "develop", webURL: nil,
                    createdAt: nil, updatedAt: nil, authorName: name)
    }
}
