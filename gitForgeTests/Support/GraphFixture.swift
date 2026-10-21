import Foundation
@testable import gitForge

/// Builders for the commit graph engine tests: a compact text format for
/// topologically ordered logs, ref shorthands, and the gitflow repo drawn in
/// `design/commit-graph/ref/01-colocacion.png`.
enum GraphFixture {
    /// One commit per line, newest first: "sha parent1 parent2". Blank lines are ignored.
    static func commits(_ text: String) -> [Commit] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let sha = words.first else { return nil }
            return Commit(sha: sha, parentShas: Array(words.dropFirst()), authorName: "T",
                          authorEmail: "t@t", authorDate: Date(timeIntervalSince1970: 0), subject: sha)
        }
    }

    static func local(_ name: String, _ sha: String, head: Bool = false,
                      upstream: String? = nil, ahead: Int? = nil, behind: Int? = nil) -> GitRef {
        GitRef(name: name, kind: .localBranch, targetSha: sha, isHead: head,
               upstream: upstream, ahead: ahead, behind: behind)
    }

    /// `name` carries the remote, as `GitCLI.refs()` returns it: "origin/x".
    static func remote(_ name: String, _ sha: String) -> GitRef {
        let remoteName = String(name.prefix { $0 != "/" })
        return GitRef(name: name, kind: .remoteBranch(remote: remoteName), targetSha: sha, isHead: false)
    }

    static func tag(_ name: String, _ sha: String) -> GitRef {
        GitRef(name: name, kind: .tag, targetSha: sha, isHead: false)
    }

    /// The gitflow repo of the reference images, topologically ordered with
    /// readable ids. `searchRanking` is row 0 and `init` row 23.
    static let gitflow: [Commit] = commits("""
        searchRanking searchUi
        searchUi searchIndex
        searchIndex mergeRelDev
        devDeps mergeRelDev
        mergeRelDev mergeHotfixDev relTypo
        cartPayment cartCheckout
        cartCheckout mergeDevIntoCart
        mergeDevIntoCart cartUi mergeLogin
        cartUi cartModel
        cartModel devBase
        mergeRelMain mergeHotfixMain relTypo
        relTypo relBump
        relBump mergeHotfixDev
        mergeHotfixDev mergeLogin hotfix
        mergeLogin devTweak loginTests
        loginTests loginApi
        loginApi loginForm
        loginForm devBase
        devTweak devBase
        devBase setup
        mergeHotfixMain setup hotfix
        hotfix setup
        setup init
        init
        """)

    /// Branches and tags of the gitflow repo. `head` names the checked-out
    /// branch; nil leaves every branch unchecked.
    static func gitflowRefs(head: String?) -> [GitRef] {
        [
            local("develop", "devDeps", head: head == "develop"),
            local("feature/cart", "cartPayment", head: head == "feature/cart"),
            local("feature/login", "loginTests", head: head == "feature/login"),
            local("feature/search", "searchRanking", head: head == "feature/search"),
            local("hotfix/crash", "hotfix", head: head == "hotfix/crash"),
            local("main", "mergeRelMain", head: head == "main"),
            local("release/1.1", "relTypo", head: head == "release/1.1"),
            tag("v1.0", "setup"),
            tag("v1.0.1", "mergeHotfixMain"),
            tag("v1.1", "mergeRelMain"),
        ]
    }

    static func row(_ sha: String, in commits: [Commit]) -> Int {
        guard let row = commits.firstIndex(where: { $0.sha == sha }) else {
            preconditionFailure("Commit \(sha) is not in the fixture")
        }
        return row
    }
}
