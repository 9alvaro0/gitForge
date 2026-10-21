import Foundation
import Testing
@testable import gitForge

@Suite("Host merge status")
struct MergeStatusMappingTests {
    @Test("GitHub mergeable_state", arguments: [
        ("clean", HostMergeStatus(verdict: .ready)),
        ("has_hooks", HostMergeStatus(verdict: .ready)),
        ("unstable", HostMergeStatus(verdict: .ready, failingChecksOptional: true)),
        ("blocked", HostMergeStatus(verdict: .blocked, reasons: ["branch protection rules"], includesLocalReasons: true)),
        ("behind", HostMergeStatus(verdict: .blocked, reasons: ["branch is out of date with main"])),
        ("dirty", HostMergeStatus(verdict: .blocked, reasons: ["conflicts with the target branch"])),
        ("draft", HostMergeStatus(verdict: .blocked, reasons: ["still a draft"])),
        ("unknown", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
        ("something_new", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
    ] as [(String, HostMergeStatus)])
    func gitHub(state: String, expected: HostMergeStatus) {
        #expect(GitHubPullRequestProvider.mergeStatus(mergeableState: state, targetBranch: "main") == expected)
    }

    @Test("GitHub without mergeable_state is still computing")
    func gitHubMissing() {
        #expect(GitHubPullRequestProvider.mergeStatus(mergeableState: nil, targetBranch: "main")
                == HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true))
    }

    @Test("GitLab detailed_merge_status: ready and waiting", arguments: [
        ("mergeable", HostMergeStatus(verdict: .ready)),
        ("checking", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
        ("unchecked", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
        ("preparing", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
        ("approvals_syncing", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
        ("ci_still_running", HostMergeStatus(verdict: .waiting, reasons: ["the pipeline is still running"])),
    ] as [(String, HostMergeStatus)])
    func gitLabOpen(detailed: String, expected: HostMergeStatus) {
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: detailed, legacy: "can_be_merged") == expected)
    }

    @Test("GitLab detailed_merge_status: blocked, one sentence per value", arguments: [
        ("not_approved", "needs approval"),
        ("ci_must_pass", "the pipeline must pass"),
        ("discussions_not_resolved", "all threads must be resolved"),
        ("conflict", "conflicts with the target branch"),
        ("draft_status", "still a draft"),
        ("need_rebase", "needs a rebase onto the target branch"),
        ("requested_changes", "a reviewer requested changes"),
        ("blocked_status", "blocked by another merge request"),
        ("merge_request_blocked", "blocked by another merge request"),
        ("not_open", "not open"),
        ("external_status_checks", "external status checks must pass"),
        ("merge_time", "can't merge before its scheduled time"),
        ("jira_association_missing", "needs a linked Jira issue"),
        ("security_policy_violations", "security policies aren't met"),
        ("title_regex", "the title doesn't match the project's rule"),
        ("commits_status", "commits don't meet the project's rules"),
        ("locked_paths", "touches locked files"),
        ("locked_lfs_files", "touches locked files"),
        ("brand_new_rule", "the host doesn't allow merging yet"),
    ])
    func gitLabBlocked(detailed: String, reason: String) {
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: detailed, legacy: "can_be_merged")
                == HostMergeStatus(verdict: .blocked, reasons: [reason]))
    }

    @Test("GitLab before 15.6 falls back to merge_status", arguments: [
        ("can_be_merged", HostMergeStatus(verdict: .ready)),
        ("cannot_be_merged", HostMergeStatus(verdict: .blocked, reasons: ["conflicts with the target branch"])),
        ("checking", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
        ("unchecked", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
        ("cannot_be_merged_recheck", HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true)),
    ] as [(String, HostMergeStatus)])
    func gitLabLegacy(legacy: String, expected: HostMergeStatus) {
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: nil, legacy: legacy) == expected)
    }

    @Test("GitLab with neither field says nothing")
    func gitLabNothing() {
        #expect(GitLabPullRequestProvider.mergeStatus(detailed: nil, legacy: nil) == nil)
    }
}

/// The detail payloads carry the merge status and whether the head lives in
/// the base repo (a fork can't have its branch deleted from here).
@Suite("Pull request detail — merge fields")
@MainActor
struct PullRequestDetailMergeFieldsTests {
    private static func gitHub(mergeableState: String?, headRepo: String?, baseRepo: String?) -> Data {
        func repo(_ name: String?) -> String { name.map { #","repo":{"full_name":"\#($0)"}"# } ?? "" }
        let state = mergeableState.map { #""mergeable_state":"\#($0)","# } ?? ""
        return Data("""
        {"id":1,"number":42,"title":"Add retry","state":"open","draft":false,"merged_at":null,\(state)
         "user":{"login":"marta"},"mergeable":true,
         "head":{"ref":"feat/sync-retry","sha":"abc"\(repo(headRepo))},
         "base":{"ref":"main"\(repo(baseRepo))}}
        """.utf8)
    }

    @Test("GitHub: mergeable_state and the head's repo")
    func gitHub() throws {
        let same = try GitHubPullRequestProvider.parseDetail(Self.gitHub(mergeableState: "behind", headRepo: "octo/app", baseRepo: "octo/app"))
        #expect(same.hostMergeStatus == HostMergeStatus(verdict: .blocked, reasons: ["branch is out of date with main"]))
        #expect(same.headInSameRepo == true)
        let fork = try GitHubPullRequestProvider.parseDetail(Self.gitHub(mergeableState: "clean", headRepo: "marta/app", baseRepo: "octo/app"))
        #expect(fork.headInSameRepo == false)
        // A deleted fork has no head repo: unknown, so nothing is offered.
        let gone = try GitHubPullRequestProvider.parseDetail(Self.gitHub(mergeableState: nil, headRepo: nil, baseRepo: "octo/app"))
        #expect(gone.headInSameRepo == nil)
        #expect(gone.hostMergeStatus?.stillComputing == true)
    }

    @Test("GitHub: whether the account can merge comes from the repo's permissions")
    func gitHubViewerCanMerge() {
        #expect(GitHubPullRequestProvider.parseViewerCanMerge(Data(#"{"permissions":{"admin":false,"push":true,"pull":true}}"#.utf8)) == true)
        #expect(GitHubPullRequestProvider.parseViewerCanMerge(Data(#"{"permissions":{"admin":false,"push":false,"pull":true}}"#.utf8)) == false)
        #expect(GitHubPullRequestProvider.parseViewerCanMerge(Data(#"{"full_name":"octo/app"}"#.utf8)) == nil)
        #expect(GitHubPullRequestProvider.parseViewerCanMerge(Data("not json".utf8)) == nil)
    }

    @Test("GitLab: whether the account can merge comes with the MR")
    func gitLabViewerCanMerge() throws {
        let fields = #"{"id":1,"iid":9,"title":"T","state":"opened","source_branch":"f","target_branch":"main""#
        #expect(try GitLabPullRequestProvider.parseDetail(Data((fields + #","user":{"can_merge":false}}"#).utf8)).viewerCanMerge == false)
        #expect(try GitLabPullRequestProvider.parseDetail(Data((fields + #","user":{"can_merge":true}}"#).utf8)).viewerCanMerge == true)
        #expect(try GitLabPullRequestProvider.parseDetail(Data((fields + "}").utf8)).viewerCanMerge == nil)
    }

    private static func gitLab(detailed: String?, legacy: String?, source: Int?, target: Int?) -> Data {
        var fields = [#""id":1"#, #""iid":9"#, #""title":"Add retry""#, #""state":"opened""#,
                      #""source_branch":"feat/sync-retry""#, #""target_branch":"main""#]
        if let detailed { fields.append(#""detailed_merge_status":"\#(detailed)""#) }
        if let legacy { fields.append(#""merge_status":"\#(legacy)""#) }
        if let source { fields.append(#""source_project_id":\#(source)"#) }
        if let target { fields.append(#""target_project_id":\#(target)"#) }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    @Test("GitLab: detailed_merge_status and the source project")
    func gitLab() throws {
        let same = try GitLabPullRequestProvider.parseDetail(Self.gitLab(detailed: "not_approved", legacy: "can_be_merged", source: 7, target: 7))
        #expect(same.hostMergeStatus == HostMergeStatus(verdict: .blocked, reasons: ["needs approval"]))
        #expect(same.headInSameRepo == true)
        let fork = try GitLabPullRequestProvider.parseDetail(Self.gitLab(detailed: nil, legacy: "can_be_merged", source: 8, target: 7))
        #expect(fork.hostMergeStatus == HostMergeStatus(verdict: .ready))
        #expect(fork.headInSameRepo == false)
        let bare = try GitLabPullRequestProvider.parseDetail(Self.gitLab(detailed: nil, legacy: nil, source: nil, target: 7))
        #expect(bare.hostMergeStatus == nil)
        #expect(bare.headInSameRepo == nil)
    }
}
