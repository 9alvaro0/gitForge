import Foundation
import Testing
@testable import gitForge

@Suite("PR providers — CI checks, reviews and summaries")
@MainActor
struct PullRequestProviderParsingTests {

    private static func data(_ json: String) -> Data { Data(json.utf8) }

    // MARK: GitHub

    @Test("Check runs map status + conclusion, duration, failure title and logs URL")
    func gitHubCheckRuns() throws {
        let checks = try GitHubPullRequestProvider.parseCheckRuns(Self.data("""
        {"total_count": 3, "check_runs": [
          {"name": "build", "status": "completed", "conclusion": "success",
           "started_at": "2026-10-11T10:00:00Z", "completed_at": "2026-10-11T10:04:12Z",
           "html_url": "https://github.com/o/r/runs/1", "app": {"name": "GitHub Actions"}},
          {"name": "perf", "status": "completed", "conclusion": "failure",
           "started_at": "2026-10-11T10:00:00Z", "completed_at": "2026-10-11T10:06:02Z",
           "html_url": "https://github.com/o/r/runs/2", "output": {"title": "p95 frame time over budget"},
           "app": {"name": "GitHub Actions"}},
          {"name": "tests", "status": "in_progress", "conclusion": null, "started_at": "2026-10-11T10:00:00Z"}
        ]}
        """))
        #expect(checks.map(\.state) == [.passed, .failed, .running])
        #expect(checks[0].duration == 252)
        #expect(checks[0].context == "GitHub Actions")
        #expect(checks[1].failureMessage == "p95 frame time over budget")
        #expect(checks[0].failureMessage == nil)
        #expect(checks[1].webURL?.absoluteString == "https://github.com/o/r/runs/2")
        #expect(checks[2].duration == nil)
    }

    @Test("Check-run states cover queued, skipped, cancelled and the failing conclusions",
          arguments: [
            ("queued", nil, CICheck.State.queued),
            ("waiting", nil, .queued),
            ("completed", "skipped", .skipped),
            ("completed", "cancelled", .canceled),
            ("completed", "timed_out", .failed),
            ("completed", "action_required", .failed),
            ("completed", "neutral", .passed),
          ] as [(String, String?, CICheck.State)])
    func gitHubCheckRunStates(status: String, conclusion: String?, expected: CICheck.State) {
        #expect(GitHubPullRequestProvider.checkRunState(status: status, conclusion: conclusion) == expected)
    }

    @Test("Commit statuses become checks with their description as the failure")
    func gitHubStatuses() throws {
        let checks = try GitHubPullRequestProvider.parseStatuses(Self.data("""
        {"state": "failure", "total_count": 2, "statuses": [
          {"state": "error", "context": "ci/jenkins", "description": "Build broke", "target_url": "https://ci/1"},
          {"state": "pending", "context": "codecov", "description": null, "target_url": null}
        ]}
        """))
        #expect(checks.map(\.state) == [.failed, .running])
        #expect(checks[0].failureMessage == "Build broke")
        #expect(checks[0].context == "Status")
    }

    @Test("Reviewers: requested are pending; others take their latest decisive review")
    func gitHubReviewers() throws {
        let reviews = try GitHubPullRequestProvider.parseReviews(Self.data("""
        [{"user": {"login": "marc"}, "state": "CHANGES_REQUESTED"},
         {"user": {"login": "marc"}, "state": "COMMENTED"},
         {"user": {"login": "marc"}, "state": "APPROVED"},
         {"user": {"login": "lucia"}, "state": "CHANGES_REQUESTED"},
         {"user": null, "state": "APPROVED"}]
        """))
        let reviewers = GitHubPullRequestProvider.reviewers(requested: ["jonas"], reviews: reviews)
        #expect(reviewers.map(\.login) == ["jonas", "marc", "lucia"])
        #expect(reviewers.map(\.state) == [.pending, .approved, .changesRequested])
    }

    // MARK: GitLab

    @Test("GitLab jobs map status, stage, duration and failure reason")
    func gitLabJobs() throws {
        let checks = try GitLabPullRequestProvider.parseJobs(Self.data("""
        [{"name": "build", "stage": "build", "status": "success", "duration": 252.4, "web_url": "https://gl/j/1"},
         {"name": "test", "stage": "test", "status": "failed", "duration": 61.0, "failure_reason": "script_failure"},
         {"name": "deploy", "stage": "deploy", "status": "manual", "duration": null},
         {"name": "lint", "stage": "test", "status": "pending", "duration": null}]
        """))
        #expect(checks.map(\.state) == [.passed, .failed, .skipped, .queued])
        #expect(checks[1].failureMessage == "script failure")
        #expect(checks[0].context == "build")
        #expect(checks[0].duration == 252.4)
    }

    @Test("Latest pipeline id, approvers, and reviewers merged with approvals")
    func gitLabPipelineAndApprovals() throws {
        #expect(try GitLabPullRequestProvider.parseLatestPipelineId(Self.data(#"[{"id": 99, "status": "running"}, {"id": 98}]"#)) == 99)
        #expect(try GitLabPullRequestProvider.parseLatestPipelineId(Self.data("[]")) == nil)
        let approvers = try GitLabPullRequestProvider.parseApprovers(Self.data("""
        {"approved_by": [{"user": {"username": "marc"}}, {"user": {"username": "priya"}}]}
        """))
        let reviewers = GitLabPullRequestProvider.reviewers(requested: ["marc", "jonas"], approvedBy: approvers)
        #expect(reviewers.map(\.login) == ["marc", "jonas", "priya"])
        #expect(reviewers.map(\.state) == [.approved, .pending, .approved])
    }

    // MARK: Summary

    @Test("Summary: a failure wins, then anything running, then a pass; empty is nil")
    func summary() {
        func check(_ state: CICheck.State) -> CICheck {
            CICheck(name: "\(state)", context: nil, state: state, duration: nil, failureMessage: nil, webURL: nil)
        }
        #expect(CIStatus.summarize([check(.passed), check(.running), check(.failed)])?.state == .failure)
        #expect(CIStatus.summarize([check(.passed), check(.queued)])?.state == .pending)
        #expect(CIStatus.summarize([check(.passed), check(.skipped)])?.state == .success)
        #expect(CIStatus.summarize([check(.canceled)])?.state == .canceled)
        #expect(CIStatus.summarize([]) == nil)
    }
}
