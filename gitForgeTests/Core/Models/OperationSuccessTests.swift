import Testing
@testable import gitForge

@Suite("OperationSuccess messages")
struct OperationSuccessTests {
    @Test("Commit names the short sha and subject; amend says so")
    func commit() {
        #expect(OperationSuccess.commit(shortSha: "abc1234", subject: "Fix it", amend: false).message
                == "Committed abc1234 — Fix it")
        #expect(OperationSuccess.commit(shortSha: "abc1234", subject: "Fix it", amend: true).message
                == "Amended abc1234 — Fix it")
        #expect(OperationSuccess.commit(shortSha: nil, subject: "Fix it", amend: false).message
                == "Committed “Fix it”")
    }

    @Test("Push counts commits and names the target")
    func push() {
        #expect(OperationSuccess.push(branch: "main", remote: "origin", ahead: 1, firstPush: false, forced: false).message
                == "Pushed 1 commit to origin/main")
        #expect(OperationSuccess.push(branch: "main", remote: "origin", ahead: 3, firstPush: false, forced: true).message
                == "Force-pushed 3 commits to origin/main")
        #expect(OperationSuccess.push(branch: "feat", remote: "origin", ahead: 0, firstPush: true, forced: false).message
                == "Published feat to origin/feat")
        #expect(OperationSuccess.push(branch: "main", remote: "origin", ahead: 0, firstPush: false, forced: false).message
                == "origin/main is already up to date")
    }

    @Test("Fetch reports what's waiting to be pulled")
    func fetch() {
        #expect(OperationSuccess.fetch(upstream: nil, behind: 0).message == "Fetched")
        #expect(OperationSuccess.fetch(upstream: "origin/main", behind: 0).message
                == "Fetched — origin/main has nothing new")
        #expect(OperationSuccess.fetch(upstream: "origin/main", behind: 2).message
                == "Fetched — 2 commits to pull from origin/main")
    }

    @Test("Pull distinguishes a no-op from new commits")
    func pull() {
        #expect(OperationSuccess.pull(upstream: "origin/main", changed: false).message == "Already up to date")
        #expect(OperationSuccess.pull(upstream: "origin/main", changed: true).message == "Pulled from origin/main")
    }

    @Test("Two identical successes are still distinct events")
    func distinctIds() {
        #expect(OperationSuccess(message: "Fetched") != OperationSuccess(message: "Fetched"))
    }
}
