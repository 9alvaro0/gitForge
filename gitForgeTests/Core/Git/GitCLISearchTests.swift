import Foundation
import Testing
@testable import gitForge

/// `GitCLI.searchLog` (#62): the arguments it builds and what real git finds with them.
@Suite("GitCLI.searchLog — History search run by git")
struct GitCLISearchTests {

    private static let refs = ["HEAD", "refs/heads/topic", "--tags"]

    private static func args(_ query: HistorySearchQuery, limit: Int = 50, skip: Int = 0) -> [String] {
        GitCLI.searchLogArguments(query, limit: limit, skip: skip, refs: refs)
    }

    // MARK: Arguments

    @Test("Each criterion is glued to its flag; the path goes after --")
    func criteria() {
        let args = Self.args(HistorySearchQuery(message: "fix", author: "ana@example.com", content: "pageEnds",
                                                path: "gitForge/Core"))
        #expect(args == ["log", "--date-order", "--format=\(GitCLI.logFormat)", "-n", "50",
                         "--regexp-ignore-case", "--fixed-strings",
                         "--grep=fix", "--author=ana@example.com", "-SpageEnds",
                         "HEAD", "refs/heads/topic", "--tags", "--", "gitForge/Core"])
    }

    @Test("Content as a regex uses -G; --skip pages like the log does")
    func regexAndSkip() throws {
        let args = Self.args(HistorySearchQuery(content: "page(Ends|Size)", contentIsRegex: true), limit: 20, skip: 40)
        #expect(args.contains("-Gpage(Ends|Size)"))
        #expect(!args.contains { $0.hasPrefix("-S") })
        let skip = try #require(args.firstIndex(of: "--skip"))
        #expect(args[skip + 1] == "40")
        let limit = try #require(args.firstIndex(of: "-n"))
        #expect(args[limit + 1] == "20")
    }

    @Test("Empty criteria add no flag, and the revisions are always closed by --")
    func emptyCriteria() {
        let args = Self.args(HistorySearchQuery(message: "  ", content: "", contentIsRegex: true))
        #expect(!args.contains { $0.hasPrefix("--grep") || $0.hasPrefix("--author") })
        #expect(!args.contains { $0.hasPrefix("-S") || $0.hasPrefix("-G") })
        #expect(args.last == "--")
        #expect(!args.contains("--skip"))
    }

    @Test("Criteria are trimmed; the regex flag only counts with content")
    func normalized() {
        let query = HistorySearchQuery(message: "  fix \n", author: "", content: " ", contentIsRegex: true, path: " a/b ")
        #expect(query.normalized == HistorySearchQuery(message: "fix", path: "a/b"))
        #expect(!query.isEmpty)
        #expect(HistorySearchQuery(message: " ", contentIsRegex: true).isEmpty)
    }

    @Test("Text that looks like an option never stands alone before --",
          arguments: ["--all", "--output=/tmp/pwned", "-p", "--exec=touch x", "HEAD", "--", "--end-of-options"])
    func noInjection(value: String) throws {
        let args = Self.args(HistorySearchQuery(message: value, author: value, content: value, path: value))
        // The options, then the app's revisions, then `--` and the path.
        let revisionsStart = try #require(args.firstIndex(of: "HEAD"))
        let separator = revisionsStart + Self.refs.count
        #expect(Array(args[revisionsStart..<separator]) == Self.refs)
        #expect(args[separator] == "--")
        // Before the revisions, the value only appears glued to its flag.
        let options = args[..<revisionsStart]
        #expect(!options.contains(value))
        #expect(options.contains("--grep=\(value)"))
        #expect(options.contains("--author=\(value)"))
        #expect(options.contains("-S\(value)"))
        // After `--`, git reads only pathspecs: the path, once.
        #expect(Array(args[(separator + 1)...]) == [value])
    }

    // MARK: Real git

    /// Five commits by two authors, oldest first, touching two files. `topic` holds a
    /// commit HEAD doesn't have.
    private static func makeRepo() async throws -> GitTestRepo {
        try await GitTestRepo.make { repo in
            func commit(_ message: String, by author: String, files: [String: String]) throws {
                for (path, text) in files { try repo.write(text, to: path) }
                try repo.git("add", "-A")
                try repo.git("commit", "-q", "--allow-empty", "-m", message, "--author", author)
            }
            try commit("Initial layout", by: "Ana Pérez <ana@example.com>",
                       files: ["Sources/Graph.swift": "let lanes = 1\n", "README.md": "# demo\n"])
            try commit("Add page ends to the graph", by: "Bo Li <bo@example.com>",
                       files: ["Sources/Graph.swift": "let lanes = 1\nlet pageEnds = [2]\n"])
            try commit("docs: mention --all and a.c", by: "Ana Pérez <ana@example.com>",
                       files: ["README.md": "# demo\nabc\n"])
            try commit("Remove page ends", by: "Bo Li <bo@example.com>",
                       files: ["Sources/Graph.swift": "let lanes = 1\n"])
            try repo.git("checkout", "-q", "-b", "topic")
            try commit("Topic work", by: "Ana Pérez <ana@example.com>", files: ["-dash.txt": "x\n"])
            try repo.git("checkout", "-q", "main")
            try commit("Bump version to abc", by: "Bo Li <bo@example.com>", files: ["VERSION": "2\n"])
        }
    }

    private static func subjects(_ repo: GitTestRepo, _ query: HistorySearchQuery,
                                 refs: [String] = ["HEAD", "topic"]) async throws -> [String] {
        try await repo.cli.searchLog(query, limit: 50, refs: refs).map(\.subject)
    }

    @Test("Message search ignores case and reads the text literally")
    func message() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        #expect(try await Self.subjects(repo, HistorySearchQuery(message: "PAGE ENDS"))
                == ["Remove page ends", "Add page ends to the graph"])
        // `a.c` is not a regex: "Bump version to abc" doesn't match.
        #expect(try await Self.subjects(repo, HistorySearchQuery(message: "a.c")) == ["docs: mention --all and a.c"])
        #expect(try await Self.subjects(repo, HistorySearchQuery(message: "--all")) == ["docs: mention --all and a.c"])
    }

    @Test("Author search matches the name or the email, ignoring case")
    func author() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let byEmail = try await Self.subjects(repo, HistorySearchQuery(author: "BO@example.com"))
        #expect(byEmail == ["Bump version to abc", "Remove page ends", "Add page ends to the graph"])
        #expect(try await Self.subjects(repo, HistorySearchQuery(author: "ana pérez")).count == 3)
    }

    @Test("Content: -S finds where a string was added or removed, -G a regex in a changed line")
    func content() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        #expect(try await Self.subjects(repo, HistorySearchQuery(content: "pageEnds"))
                == ["Remove page ends", "Add page ends to the graph"])
        #expect(try await Self.subjects(repo, HistorySearchQuery(content: "page[A-Z]nds", contentIsRegex: true))
                == ["Remove page ends", "Add page ends to the graph"])
        // Literal for -S: the brackets are not a class.
        #expect(try await Self.subjects(repo, HistorySearchQuery(content: "page[A-Z]nds")).isEmpty)
    }

    @Test("Path search lists the commits that touch a file or folder, even one named like an option")
    func path() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        #expect(try await Self.subjects(repo, HistorySearchQuery(path: "Sources"))
                == ["Remove page ends", "Add page ends to the graph", "Initial layout"])
        #expect(try await Self.subjects(repo, HistorySearchQuery(path: "-dash.txt")) == ["Topic work"])
    }

    @Test("Criteria combine with AND, over the revisions given")
    func combined() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        #expect(try await Self.subjects(repo, HistorySearchQuery(message: "page", author: "bo@", content: "pageEnds",
                                                                  path: "Sources/Graph.swift"))
                == ["Remove page ends", "Add page ends to the graph"])
        #expect(try await Self.subjects(repo, HistorySearchQuery(message: "remove", author: "ana@")).isEmpty)
        // `Topic work` is only on topic: not in HEAD's walk.
        #expect(try await Self.subjects(repo, HistorySearchQuery(author: "ana@"), refs: ["HEAD"])
                == ["docs: mention --all and a.c", "Initial layout"])
    }

    @Test("Results page with -n and --skip")
    func paging() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        let query = HistorySearchQuery(author: "example.com")
        let first = try await repo.cli.searchLog(query, limit: 2, skip: 0, refs: ["HEAD"]).map(\.subject)
        let second = try await repo.cli.searchLog(query, limit: 2, skip: 2, refs: ["HEAD"]).map(\.subject)
        let third = try await repo.cli.searchLog(query, limit: 2, skip: 4, refs: ["HEAD"]).map(\.subject)
        #expect(first == ["Bump version to abc", "Remove page ends"])
        #expect(second == ["docs: mention --all and a.c", "Add page ends to the graph"])
        #expect(third == ["Initial layout"])
    }

    @Test("An invalid regex is a git error, not an empty result")
    func invalidRegex() async throws {
        let repo = try await Self.makeRepo()
        defer { repo.remove() }
        await #expect(throws: GitError.self) {
            _ = try await repo.cli.searchLog(HistorySearchQuery(content: "page(", contentIsRegex: true),
                                             limit: 10, refs: ["HEAD"])
        }
    }

    @Test("trackedFiles lists the index, names with spaces and dashes included")
    func trackedFiles() async throws {
        let repo = try await GitTestRepo.make { repo in
            try repo.commit("files", files: ["a b/c.txt": "1", "-x.txt": "2", "z.md": "3"])
            try repo.write("untracked", to: "new.txt")
        }
        defer { repo.remove() }
        #expect(try await repo.cli.trackedFiles().sorted() == ["-x.txt", "a b/c.txt", "z.md"])
    }
}
