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
}
