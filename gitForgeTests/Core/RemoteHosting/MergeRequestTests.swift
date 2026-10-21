import Foundation
import Testing
@testable import gitForge

private func pull(number: Int = 42, title: String = "Add retry", source: String = "feat/sync-retry") -> PullRequest {
    PullRequest(id: "\(number)", number: number, title: title, state: .open, authorLogin: "marta", authorAvatarURL: nil,
                sourceBranch: source, targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil, headSha: "abc")
}

private func detail(_ pull: PullRequest, description: String? = "Retries failed syncs.", sameRepo: Bool? = true) -> PullRequestDetail {
    PullRequestDetail(pull: pull, descriptionMarkdown: description, labels: [], reviewers: [], assignees: [],
                      mergeable: true, ciStatus: nil, headInSameRepo: sameRepo)
}

private func commit(_ subject: String) -> PullRequestCommit {
    PullRequestCommit(sha: UUID().uuidString, subject: subject, authorName: nil, authorDate: nil)
}

private func json(_ request: URLRequest) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? NSDictionary)
}

@Suite("Merge requests and options")
@MainActor
struct MergeRequestTests {
    static let github = RemoteHost(provider: .github, host: "github.com", owner: "octo", repo: "app")
    static let gitlab = RemoteHost(provider: .gitlab, host: "gitlab.example.test", owner: "group/sub", repo: "app",
                                   apiBaseURL: URL(string: "https://gitlab.example.test/api/v4"))

    // MARK: GitHub

    @Test("GitHub settings read from the repo")
    func gitHubSettings() throws {
        let settings = try GitHubPullRequestProvider.parseMergeSettings(Fixture.data("github-repo-merge-settings"))
        #expect(settings == GitHubMergeSettings(allowSquash: true, allowMerge: true, allowRebase: false,
                                                squashTitle: "PR_TITLE", squashMessage: "COMMIT_MESSAGES",
                                                mergeTitle: "MERGE_MESSAGE", mergeMessage: "PR_BODY"))
        #expect(try GitHubPullRequestProvider.parseMergeSettings(Data("{}".utf8)) == GitHubMergeSettings())
    }

    @Test("GitHub options follow the repo's settings and prefill only exact defaults")
    func gitHubOptions() throws {
        let settings = try GitHubPullRequestProvider.parseMergeSettings(Fixture.data("github-repo-merge-settings"))
        let pr = pull()
        let options = GitHubPullRequestProvider.mergeOptions(settings: settings, pull: pr, detail: detail(pr), commits: [])
        #expect(options.kind == .github(methods: [.squash, .merge]))
        #expect(options.initialMethod == .squash)
        #expect(options.canDeleteSourceBranch)
        #expect(options.defaults(for: .squash)[.title] == "Add retry (#42)")
        #expect(options.defaults(for: .squash)[.body] == nil)
        #expect(options.defaults(for: .merge)[.title] == nil)
        #expect(options.defaults(for: .merge)[.body] == "Retries failed syncs.")
    }

    @Test("GitHub prefill table (Ruling 4)")
    func gitHubPrefill() {
        let pr = pull()
        func options(_ settings: GitHubMergeSettings, commits: [PullRequestCommit] = [], description: String? = "Body") -> MergeOptions {
            GitHubPullRequestProvider.mergeOptions(settings: settings, pull: pr, detail: detail(pr, description: description), commits: commits)
        }
        let one = options(.init(squashTitle: "COMMIT_OR_PR_TITLE"), commits: [commit("Fix flaky retry")])
        #expect(one.defaults(for: .squash)[.title] == "Fix flaky retry (#42)")
        let two = options(.init(squashTitle: "COMMIT_OR_PR_TITLE"), commits: [commit("a"), commit("b")])
        #expect(two.defaults(for: .squash)[.title] == "Add retry (#42)")
        #expect(options(.init(squashMessage: "PR_BODY")).defaults(for: .squash)[.body] == "Body")
        #expect(options(.init(squashMessage: "PR_BODY"), description: nil).defaults(for: .squash)[.body] == "")
        #expect(options(.init(squashMessage: "BLANK")).defaults(for: .squash)[.body] == "")
        let merge = options(.init(mergeTitle: "PR_TITLE", mergeMessage: "PR_TITLE"))
        #expect(merge.defaults(for: .merge) == [.title: "Add retry (#42)", .body: "Add retry"])
        #expect(options(.init(mergeMessage: "BLANK")).defaults(for: .merge) == [.body: ""])
        #expect(options(.init()).defaultsByMethod.values.allSatisfy { $0.isEmpty })
        #expect(options(.init()).defaults(for: .rebase).isEmpty)
    }

    @Test("GitHub methods: unknown counts as allowed; squash first when allowed")
    func gitHubMethods() {
        let pr = pull()
        func methods(_ settings: GitHubMergeSettings) -> MergeOptions {
            GitHubPullRequestProvider.mergeOptions(settings: settings, pull: pr, detail: detail(pr), commits: [])
        }
        #expect(methods(.init()).kind == .github(methods: [.squash, .merge, .rebase]))
        let noSquash = methods(.init(allowSquash: false, allowMerge: false, allowRebase: true))
        #expect(noSquash.kind == .github(methods: [.rebase]))
        #expect(noSquash.initialMethod == .rebase)
        // Nothing allowed can't happen on GitHub: offer all and let it answer.
        #expect(methods(.init(allowSquash: false, allowMerge: false, allowRebase: false)).kind == .github(methods: [.squash, .merge, .rebase]))
    }

    @Test("A fork or an unknown head repo can't delete")
    func gitHubFork() {
        let pr = pull()
        #expect(!GitHubPullRequestProvider.mergeOptions(settings: .init(), pull: pr, detail: detail(pr, sameRepo: false), commits: []).canDeleteSourceBranch)
        #expect(!GitHubPullRequestProvider.mergeOptions(settings: .init(), pull: pr, detail: detail(pr, sameRepo: nil), commits: []).canDeleteSourceBranch)
    }

    @Test("GitHub merge: PUT with method and sha; delete keeps slashes")
    func gitHubRequests() throws {
        let input = MergeInput(method: .squash, squash: false, deleteSourceBranch: true, messages: [:], headSha: "abc")
        let merge = GitHubPullRequestProvider.mergeRequest(host: Self.github, number: 42, input: input, token: "t")
        #expect(merge.httpMethod == "PUT")
        #expect(merge.url?.absoluteString == "https://api.github.com/repos/octo/app/pulls/42/merge")
        #expect(try json(merge) == ["merge_method": "squash", "sha": "abc"])
        #expect(merge.value(forHTTPHeaderField: "Authorization") == "Bearer t")
        let delete = GitHubPullRequestProvider.deleteBranchRequest(host: Self.github, branch: "feat/sync-retry", token: "t")
        #expect(delete.httpMethod == "DELETE")
        #expect(delete.url?.absoluteString == "https://api.github.com/repos/octo/app/git/refs/heads/feat/sync-retry")
        let odd = GitHubPullRequestProvider.deleteBranchRequest(host: Self.github, branch: "fix/a b#1?", token: "t")
        #expect(odd.url?.absoluteString == "https://api.github.com/repos/octo/app/git/refs/heads/fix/a%20b%231%3F")
        #expect(GitHubPullRequestProvider.repoRequest(host: Self.github, token: "t").url?.absoluteString
                == "https://api.github.com/repos/octo/app")
    }

    @Test("GitHub merge carries only the edited title and body")
    func gitHubMessages() throws {
        let input = MergeInput(method: .merge, squash: false, deleteSourceBranch: false,
                               messages: [.title: "Retry policy", .body: "Why"], headSha: nil)
        let merge = GitHubPullRequestProvider.mergeRequest(host: Self.github, number: 42, input: input, token: "t")
        #expect(try json(merge) == ["merge_method": "merge", "commit_title": "Retry policy", "commit_message": "Why"])
    }

    // MARK: GitLab

    @Test("GitLab merge sends squash and branch removal, and only edited messages")
    func gitLabRequest() throws {
        let input = MergeInput(method: nil, squash: true, deleteSourceBranch: true, messages: [.squashMessage: "Squashed"], headSha: "def")
        let merge = GitLabPullRequestProvider.mergeRequest(host: Self.gitlab, number: 9, input: input, token: "t")
        #expect(merge.httpMethod == "PUT")
        #expect(merge.url?.absoluteString == "https://gitlab.example.test/api/v4/projects/group%2Fsub%2Fapp/merge_requests/9/merge")
        #expect(try json(merge) == ["squash": true, "should_remove_source_branch": true, "sha": "def",
                                    "squash_commit_message": "Squashed"])
        let plain = MergeInput(method: nil, squash: false, deleteSourceBranch: false, messages: [.mergeMessage: "Merge it"], headSha: nil)
        #expect(try json(GitLabPullRequestProvider.mergeRequest(host: Self.gitlab, number: 9, input: plain, token: "t"))
                == ["squash": false, "should_remove_source_branch": false, "merge_commit_message": "Merge it"])
        #expect(GitLabPullRequestProvider.projectRequest(host: Self.gitlab, token: "t").url?.absoluteString
                == "https://gitlab.example.test/api/v4/projects/group%2Fsub%2Fapp")
    }

    @Test("GitLab project settings default safely")
    func gitLabSettings() throws {
        let parsed = try GitLabPullRequestProvider.parseProjectMergeSettings(Fixture.data("gitlab-project-merge-settings"))
        #expect(parsed.method == .fastForward && parsed.squash == .always)
        let empty = try GitLabPullRequestProvider.parseProjectMergeSettings(Data("{}".utf8))
        #expect(empty.method == .merge && empty.squash == .defaultOff)
        let unknown = try GitLabPullRequestProvider.parseProjectMergeSettings(Data(#"{"merge_method":"semi_linear","squash_option":"sometimes"}"#.utf8))
        #expect(unknown.method == .merge && unknown.squash == .defaultOff)
    }
}

/// The merge calls against a stub server: what gets sent, in which order,
/// and what a failed branch deletion or a refused merge turns into.
@Suite("Merge flow")
@MainActor
struct MergeFlowTests {
    private static func gitHub() -> (StubServer, GitHubPullRequestProvider, RemoteHost) {
        let server = StubServer()
        let host = RemoteHost(provider: .github, host: server.host, owner: "octo", repo: "app",
                              apiBaseURL: URL(string: "https://\(server.host)/api/v3"))
        return (server, GitHubPullRequestProvider(session: server.http.session), host)
    }

    private static func gitLab() -> (StubServer, GitLabPullRequestProvider, RemoteHost) {
        let server = StubServer()
        let host = RemoteHost(provider: .gitlab, host: server.host, owner: "group", repo: "app",
                              apiBaseURL: URL(string: "https://\(server.host)/api/v4"))
        return (server, GitLabPullRequestProvider(session: server.http.session), host)
    }

    static let ghMerge = "/api/v3/repos/octo/app/pulls/42/merge"
    static let ghRef = "/api/v3/repos/octo/app/git/refs/heads/feat/sync-retry"
    static let squashAndDelete = MergeInput(method: .squash, squash: false, deleteSourceBranch: true, messages: [:], headSha: "abc")

    @Test("GitHub: merge, then delete the branch")
    func gitHubMergeAndDelete() async throws {
        let (server, provider, host) = Self.gitHub()
        server.on("PUT", Self.ghMerge, body: Data(#"{"merged":true,"sha":"fff"}"#.utf8))
        server.on("DELETE", Self.ghRef, status: 204)
        let outcome = try await provider.merge(host: host, pull: pull(), input: Self.squashAndDelete, token: "t")
        #expect(outcome == MergeOutcome(branchDeleted: true))
        #expect(server.requests.map { "\($0.method) \($0.path)" } == ["PUT \(Self.ghMerge)", "DELETE \(Self.ghRef)"])
        #expect(server.requests.first?.json?["merge_method"] as? String == "squash")
    }

    @Test("GitHub: a branch the repo already deleted counts as deleted", arguments: [404, 422])
    func gitHubAlreadyDeleted(status: Int) async throws {
        let (server, provider, host) = Self.gitHub()
        server.on("PUT", Self.ghMerge, body: Data(#"{"merged":true}"#.utf8))
        server.on("DELETE", Self.ghRef, status: status, body: Data(#"{"message":"Reference does not exist"}"#.utf8))
        #expect(try await provider.merge(host: host, pull: pull(), input: Self.squashAndDelete, token: "t") == MergeOutcome(branchDeleted: true))
    }

    @Test("GitHub: a refused delete (protected branch) is a 422 too, and reports the branch kept")
    func gitHubDeleteRefused() async throws {
        let (server, provider, host) = Self.gitHub()
        server.on("PUT", Self.ghMerge, body: Data(#"{"merged":true}"#.utf8))
        server.on("DELETE", Self.ghRef, status: 422, body: Data(#"{"message":"Cannot delete a protected branch"}"#.utf8))
        #expect(try await provider.merge(host: host, pull: pull(), input: Self.squashAndDelete, token: "t") == MergeOutcome(branchDeleted: false))
    }

    @Test("GitHub: a failed delete keeps the merge and reports the branch kept")
    func gitHubDeleteFails() async throws {
        let (server, provider, host) = Self.gitHub()
        server.on("PUT", Self.ghMerge, body: Data(#"{"merged":true}"#.utf8))
        server.on("DELETE", Self.ghRef, status: 403, body: Data("{}".utf8))
        #expect(try await provider.merge(host: host, pull: pull(), input: Self.squashAndDelete, token: "t") == MergeOutcome(branchDeleted: false))
    }

    @Test("GitHub: no delete asked, no DELETE sent")
    func gitHubKeepBranch() async throws {
        let (server, provider, host) = Self.gitHub()
        server.on("PUT", Self.ghMerge, body: Data(#"{"merged":true}"#.utf8))
        var input = Self.squashAndDelete
        input.deleteSourceBranch = false
        _ = try await provider.merge(host: host, pull: pull(), input: input, token: "t")
        #expect(server.requests("DELETE", Self.ghRef).isEmpty)
    }

    @Test("GitHub: a refused merge throws and deletes nothing")
    func gitHubRefused() async {
        let (server, provider, host) = Self.gitHub()
        server.on("PUT", Self.ghMerge, status: 409, body: Data(#"{"message":"Head branch was modified. Review and try the merge again."}"#.utf8))
        await #expect(throws: PullRequestFetchError.self) {
            try await provider.merge(host: host, pull: pull(), input: Self.squashAndDelete, token: "t")
        }
        #expect(server.requests("DELETE", Self.ghRef).isEmpty)
    }

    @Test("GitHub: options come from the repo")
    func gitHubFetchOptions() async throws {
        let (server, provider, host) = Self.gitHub()
        server.on("GET", "/api/v3/repos/octo/app", fixture: "github-repo-merge-settings")
        let pr = pull()
        let options = try await provider.fetchMergeOptions(host: host, pull: pr, detail: detail(pr), commits: [], token: "t")
        #expect(options.kind == .github(methods: [.squash, .merge]))
    }

    static let glMerge = "/api/v4/projects/group/app/merge_requests/9/merge"

    @Test("GitLab: one PUT; the branch removal rides along")
    func gitLabMerge() async throws {
        let (server, provider, host) = Self.gitLab()
        server.on("PUT", Self.glMerge, body: Data(#"{"state":"merged"}"#.utf8))
        let input = MergeInput(method: nil, squash: true, deleteSourceBranch: true, messages: [:], headSha: "def")
        #expect(try await provider.merge(host: host, pull: pull(number: 9), input: input, token: "t") == MergeOutcome(branchDeleted: true))
        #expect(server.requests.map { "\($0.method) \($0.path)" } == ["PUT \(Self.glMerge)"])
        #expect(server.requests.first?.json?["should_remove_source_branch"] as? Bool == true)
    }

    @Test("GitLab: a 401 with a working token means no merge rights, not a dead token")
    func gitLabRefused() async {
        let (server, provider, host) = Self.gitLab()
        server.on("PUT", Self.glMerge, status: 401, body: Data(#"{"message":"401 Unauthorized"}"#.utf8))
        server.on("GET", "/api/v4/user", fixture: "gitlab-user")
        let input = MergeInput(method: nil, squash: false, deleteSourceBranch: false, messages: [:], headSha: nil)
        await #expect(throws: PullRequestActionError.forbidden) {
            try await provider.merge(host: host, pull: pull(number: 9), input: input, token: "t")
        }
    }

    @Test("GitLab: a 401 with a dead token stays a 401, so the token gets refreshed")
    func gitLabDeadToken() async {
        let (server, provider, host) = Self.gitLab()
        server.on("PUT", Self.glMerge, status: 401, body: Data("{}".utf8))
        server.on("GET", "/api/v4/user", status: 401, body: Data("{}".utf8))
        let input = MergeInput(method: nil, squash: false, deleteSourceBranch: false, messages: [:], headSha: nil)
        await #expect(throws: PullRequestFetchError.unauthorized) {
            try await provider.merge(host: host, pull: pull(number: 9), input: input, token: "t")
        }
    }

    @Test("GitLab: options come from the project")
    func gitLabFetchOptions() async throws {
        let (server, provider, host) = Self.gitLab()
        server.on("GET", "/api/v4/projects/group/app", fixture: "gitlab-project-merge-settings")
        let pr = pull(number: 9)
        let options = try await provider.fetchMergeOptions(host: host, pull: pr, detail: detail(pr, sameRepo: false), commits: [], token: "t")
        #expect(options.kind == .gitlab(method: .fastForward, squash: .always))
        #expect(options.initialSquash)
        #expect(!options.canDeleteSourceBranch)
        #expect(options.initialMethod == nil)
    }
}
