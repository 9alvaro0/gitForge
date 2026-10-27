import Foundation
import Testing
@testable import gitForge

@Suite("PullListStatus — a row's verdict")
struct PullListStatusTests {

    // MARK: GitLab

    @Test("GitLab: each detailed_merge_status maps to its verdict", arguments: [
        ("mergeable", PullListStatus.Kind.ready),
        ("checking", .checking), ("unchecked", .checking), ("preparing", .checking), ("approvals_syncing", .checking),
        ("ci_still_running", .running),
        ("ci_must_pass", .failing),
        ("conflict", .conflicts),
        ("need_rebase", .behind),
        ("not_approved", .needsApproval),
        ("requested_changes", .changesRequested),
        ("discussions_not_resolved", .unresolvedThreads),
        ("blocked_status", .blocked), ("merge_request_blocked", .blocked), ("jira_association_missing", .blocked),
        ("something_new", .blocked),
    ])
    func gitLabDetailed(code: String, kind: PullListStatus.Kind) {
        let status = PullListStatus.gitLab(detailed: code, legacy: "can_be_merged", hasConflicts: false)
        #expect(status == PullListStatus(kind: kind, hostCode: code))
    }

    @Test("GitLab: a draft or a merge request that isn't open says nothing")
    func gitLabNoVerdict() {
        #expect(PullListStatus.gitLab(detailed: "draft_status", legacy: nil, hasConflicts: nil) == nil)
        #expect(PullListStatus.gitLab(detailed: "not_open", legacy: nil, hasConflicts: nil) == nil)
        #expect(PullListStatus.gitLab(detailed: nil, legacy: nil, hasConflicts: nil) == nil)
    }

    @Test("GitLab before 15.6: has_conflicts, then merge_status")
    func gitLabLegacy() {
        #expect(PullListStatus.gitLab(detailed: nil, legacy: "can_be_merged", hasConflicts: true)?.kind == .conflicts)
        #expect(PullListStatus.gitLab(detailed: nil, legacy: "can_be_merged", hasConflicts: false)?.kind == .ready)
        #expect(PullListStatus.gitLab(detailed: nil, legacy: "cannot_be_merged", hasConflicts: nil)?.kind == .conflicts)
        #expect(PullListStatus.gitLab(detailed: nil, legacy: "unchecked", hasConflicts: nil)?.kind == .checking)
    }

    @Test("A blocked verdict names GitLab's reason when gitForge knows it")
    func blockedHelp() {
        let known = PullListStatus(kind: .blocked, hostCode: "blocked_status").help
        #expect(known.contains("blocked by another merge request"))
        let unknown = PullListStatus(kind: .blocked, hostCode: "something_new").help
        #expect(unknown == String(localized: "The host doesn't allow merging it yet."))
        #expect(GitLabPullRequestProvider.knownBlockedReason("something_new") == nil)
    }

    // MARK: GitHub

    @Test("GitHub: conflicts come before everything else")
    func gitHubConflictsFirst() {
        let status = PullListStatus.gitHub(mergeable: "CONFLICTING", mergeState: "BLOCKED",
                                           reviewDecision: "REVIEW_REQUIRED", checks: "FAILURE")
        #expect(status?.kind == .conflicts)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "DIRTY", reviewDecision: nil,
                                      checks: nil)?.kind == .conflicts)
    }

    @Test("GitHub: failing then running checks, before the review decision")
    func gitHubChecks() {
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "BLOCKED", reviewDecision: "REVIEW_REQUIRED",
                                      checks: "FAILURE")?.kind == .failing)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "UNSTABLE", reviewDecision: nil,
                                      checks: "ERROR")?.kind == .failing)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "BLOCKED", reviewDecision: "REVIEW_REQUIRED",
                                      checks: "PENDING")?.kind == .running)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "CLEAN", reviewDecision: nil,
                                      checks: "EXPECTED")?.kind == .running)
    }

    @Test("GitHub: the review decision, then the merge state")
    func gitHubReviewsThenState() {
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "BLOCKED", reviewDecision: "CHANGES_REQUESTED",
                                      checks: "SUCCESS")?.kind == .changesRequested)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "BLOCKED", reviewDecision: "REVIEW_REQUIRED",
                                      checks: "SUCCESS")?.kind == .needsApproval)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "BEHIND", reviewDecision: "APPROVED",
                                      checks: "SUCCESS")?.kind == .behind)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "BLOCKED", reviewDecision: "APPROVED",
                                      checks: "SUCCESS")?.kind == .blocked)
        for state in ["CLEAN", "HAS_HOOKS", "UNSTABLE"] {
            #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: state, reviewDecision: nil,
                                          checks: nil)?.kind == .ready)
        }
    }

    @Test("GitHub without a merge state: mergeable alone decides, and a draft says nothing")
    func gitHubWithoutMergeState() {
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: nil, reviewDecision: nil, checks: nil)?.kind == .ready)
        #expect(PullListStatus.gitHub(mergeable: "UNKNOWN", mergeState: nil, reviewDecision: nil, checks: nil)?.kind == .checking)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "UNKNOWN", reviewDecision: nil,
                                      checks: nil)?.kind == .ready)
        #expect(PullListStatus.gitHub(mergeable: "MERGEABLE", mergeState: "DRAFT", reviewDecision: nil, checks: nil) == nil)
    }

    // MARK: Tones

    @Test("Each verdict's tone")
    func tones() {
        let tones = Dictionary(uniqueKeysWithValues: PullListStatus.Kind.allCases.map { ($0, $0.tone) })
        #expect(tones[.ready] == .ok)
        #expect(tones[.checking] == .info && tones[.running] == .info)
        #expect([tones[.behind], tones[.needsApproval], tones[.changesRequested], tones[.unresolvedThreads]]
            .allSatisfy { $0 == .warn })
        #expect([tones[.failing], tones[.conflicts], tones[.blocked]].allSatisfy { $0 == .danger })
    }

    @Test("A draft, a silent host, a merged or a closed one are neutral; only an open ready one offers Merge")
    func rowTone() {
        let ready = PullListStatus(kind: .ready)
        #expect(Self.pull(.open, ready).statusTone == .ok)
        #expect(Self.pull(.open, ready).isReadyToMerge)
        #expect(Self.pull(.open, nil).statusTone == .neutral)
        #expect(!Self.pull(.open, nil).isReadyToMerge)
        for state in [PullRequest.State.draft, .merged, .closed] {
            #expect(Self.pull(state, ready).statusTone == .neutral)
            #expect(!Self.pull(state, ready).isReadyToMerge)
        }
        #expect(!Self.pull(.open, PullListStatus(kind: .blocked)).isReadyToMerge)
    }

    @Test("A heading's summary: what needs attention first, tones with none left out")
    func summary() {
        let pulls = [Self.pull(.open, PullListStatus(kind: .ready)), Self.pull(.draft, nil),
                     Self.pull(.open, PullListStatus(kind: .conflicts)), Self.pull(.open, PullListStatus(kind: .ready)),
                     Self.pull(.open, PullListStatus(kind: .failing))]
        #expect(PullStatusTone.summary(of: pulls) == [PullToneCount(tone: .danger, count: 2),
                                                      PullToneCount(tone: .ok, count: 2),
                                                      PullToneCount(tone: .neutral, count: 1)])
        #expect(PullStatusTone.summary(of: []).isEmpty)
    }

    // MARK: Snapshot

    @Test("A pull request saved before verdicts existed still decodes, and one with a verdict round-trips")
    func codable() throws {
        let old = #"{"id":"1","number":1,"title":"T","state":"open","sourceBranch":"f","targetBranch":"main"}"#
        let decoded = try JSONDecoder().decode(PullRequest.self, from: Data(old.utf8))
        #expect(decoded.listStatus == nil)

        let pull = Self.pull(.open, PullListStatus(kind: .blocked, hostCode: "blocked_status"))
        let again = try JSONDecoder().decode(PullRequest.self, from: JSONEncoder().encode(pull))
        #expect(again == pull)
    }

    private static func pull(_ state: PullRequest.State, _ status: PullListStatus?) -> PullRequest {
        PullRequest(id: "1", number: 1, title: "T", state: state, authorLogin: nil, authorAvatarURL: nil,
                    sourceBranch: "f", targetBranch: "main", webURL: nil, createdAt: nil, updatedAt: nil,
                    listStatus: status)
    }
}
