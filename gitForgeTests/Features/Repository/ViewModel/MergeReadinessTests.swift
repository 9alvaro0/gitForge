import Foundation
import Testing
@testable import gitForge

@Suite("Pull request merge banner")
struct MergeReadinessTests {

    private static func check(_ state: CICheck.State) -> CICheck {
        CICheck(name: UUID().uuidString, context: nil, state: state, duration: nil, failureMessage: nil, webURL: nil)
    }

    @Test("Failing checks, conflicts or requested changes block it; reasons and counts say why")
    func blocked() {
        let readiness = MergeReadiness.evaluate(
            state: .open, mergeable: false,
            checks: [Self.check(.passed), Self.check(.passed), Self.check(.failed), Self.check(.running)],
            reviewers: [.init(login: "a", state: .changesRequested), .init(login: "b", state: .pending)]
        )
        #expect(readiness?.kind == .blocked)
        #expect(readiness?.reasons == ["conflicts with the target branch", "1 failing check",
                                       "1 review requesting changes", "1 in progress", "1 review pending"])
        #expect(readiness?.passed == 2 && readiness?.failed == 1 && readiness?.running == 1)
    }

    @Test("Only running checks or pending reviews: waiting")
    func waiting() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true,
                                                checks: [Self.check(.queued)],
                                                reviewers: [.init(login: "a", state: .pending), .init(login: "b", state: .pending)])
        #expect(readiness?.kind == .waiting)
        #expect(readiness?.reasons == ["1 in progress", "2 reviews pending"])
    }

    @Test("All green is ready; drafts are blocked; closed and merged PRs get no banner")
    func others() {
        #expect(MergeReadiness.evaluate(state: .open, mergeable: true, checks: [Self.check(.passed)],
                                        reviewers: [.init(login: "a", state: .approved)])?.kind == .ready)
        #expect(MergeReadiness.evaluate(state: .draft, mergeable: true, checks: [], reviewers: [])?.kind == .blocked)
        #expect(MergeReadiness.evaluate(state: .merged, mergeable: nil, checks: [], reviewers: []) == nil)
        #expect(MergeReadiness.evaluate(state: .closed, mergeable: nil, checks: [], reviewers: []) == nil)
    }

    // MARK: The host's verdict

    @Test("The host's verdict wins: optional failing checks don't block")
    func unstable() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [Self.check(.failed), Self.check(.passed)],
                                                reviewers: [], hostStatus: HostMergeStatus(verdict: .ready, failingChecksOptional: true))
        #expect(readiness?.kind == .ready)
        #expect(readiness?.canMerge == true)
        #expect(readiness?.reasons == ["1 check failing (not required)"])
        #expect(readiness?.failed == 1 && readiness?.passed == 1)
    }

    @Test("Several optional failing checks are counted")
    func unstableMany() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [Self.check(.failed), Self.check(.failed)],
                                                reviewers: [], hostStatus: HostMergeStatus(verdict: .ready, failingChecksOptional: true))
        #expect(readiness?.reasons == ["2 checks failing (not required)"])
    }

    @Test("GitHub blocked explains with what gitForge knows, then branch protection")
    func gitHubBlocked() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [Self.check(.failed)],
                                                reviewers: [.init(login: "a", state: .pending)],
                                                hostStatus: HostMergeStatus(verdict: .blocked, reasons: ["branch protection rules"], includesLocalReasons: true))
        #expect(readiness?.kind == .blocked)
        #expect(readiness?.reasons == ["1 failing check", "1 review pending", "branch protection rules"])
        #expect(readiness?.canMerge == false)
    }

    @Test("GitLab's reason stands alone, whatever gitForge would have said")
    func gitLabBlocked() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: false, checks: [Self.check(.failed)],
                                                reviewers: [.init(login: "a", state: .changesRequested)],
                                                hostStatus: HostMergeStatus(verdict: .blocked, reasons: ["all threads must be resolved"]))
        #expect(readiness?.reasons == ["all threads must be resolved"])
        #expect(readiness?.failed == 1)
    }

    @Test("Ready on the host merges even with checks gitForge would call failing")
    func hostReady() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: nil, checks: [Self.check(.running)],
                                                reviewers: [.init(login: "a", state: .pending)],
                                                hostStatus: HostMergeStatus(verdict: .ready))
        #expect(readiness?.kind == .ready)
        #expect(readiness?.reasons == [])
        #expect(readiness?.running == 1)
    }

    @Test("Waiting on the host can't merge; closed PRs still get nothing")
    func hostWaiting() {
        let waiting = MergeReadiness.evaluate(state: .open, mergeable: nil, checks: [], reviewers: [],
                                              hostStatus: HostMergeStatus(verdict: .waiting, reasons: ["checking mergeability…"], stillComputing: true))
        #expect(waiting?.kind == .waiting)
        #expect(waiting?.canMerge == false)
        #expect(MergeReadiness.evaluate(state: .merged, mergeable: nil, checks: [], reviewers: [],
                                        hostStatus: HostMergeStatus(verdict: .ready)) == nil)
    }

    @Test("A draft never merges, even when the host calls it clean (GitHub does)")
    func draftOverHostReady() {
        let readiness = MergeReadiness.evaluate(state: .draft, mergeable: true, checks: [], reviewers: [],
                                                hostStatus: HostMergeStatus(verdict: .ready))
        #expect(readiness?.kind == .blocked)
        #expect(readiness?.reasons == ["still a draft"])
        #expect(readiness?.canMerge == false)
        // GitLab's draft_status already says so: not twice.
        #expect(MergeReadiness.evaluate(state: .draft, mergeable: true, checks: [], reviewers: [],
                                        hostStatus: HostMergeStatus(verdict: .blocked, reasons: ["still a draft"]))?.reasons
                == ["still a draft"])
    }

    @Test("An account that can't merge: the PR's state stands, Merge… doesn't, and the banner says why")
    func accountCantMerge() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [], reviewers: [],
                                                hostStatus: HostMergeStatus(verdict: .ready), viewerCanMerge: false)
        #expect(readiness?.kind == .ready)
        #expect(readiness?.canMerge == false)
        #expect(readiness?.summary == "Your account can't merge it.")
        #expect(MergeReadiness.evaluate(state: .open, mergeable: true, checks: [], reviewers: [],
                                        hostStatus: HostMergeStatus(verdict: .ready), viewerCanMerge: true)?.canMerge == true)
    }

    @Test("Without the host's say, nothing merges from here")
    func noHostStatus() {
        #expect(MergeReadiness.evaluate(state: .open, mergeable: true, checks: [], reviewers: [])?.canMerge == false)
    }

    @Test("The summary is the banner's sentence: joined, capitalized, with a full stop")
    func summary() {
        let readiness = MergeReadiness.evaluate(state: .open, mergeable: true, checks: [Self.check(.failed)],
                                                reviewers: [.init(login: "a", state: .pending)],
                                                hostStatus: HostMergeStatus(verdict: .blocked, reasons: ["branch protection rules"], includesLocalReasons: true))
        #expect(readiness?.summary == "1 failing check · 1 review pending · branch protection rules.")
        #expect(MergeReadiness.evaluate(state: .open, mergeable: true, checks: [], reviewers: [],
                                        hostStatus: HostMergeStatus(verdict: .blocked, reasons: ["all threads must be resolved"]))?.summary
                == "All threads must be resolved.")
        #expect(MergeReadiness.evaluate(state: .open, mergeable: true, checks: [], reviewers: [],
                                        hostStatus: HostMergeStatus(verdict: .ready))?.summary == nil)
    }
}
