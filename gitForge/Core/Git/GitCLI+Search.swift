import Foundation

extension GitCLI {
    /// One page of the commits in `refs`' walk that match `query` (#62): the same walk,
    /// order and format as `log(limit:skip:refs:)`, so a result reads like a log row and
    /// `--skip` pages it the same way.
    func searchLog(_ query: HistorySearchQuery, limit: Int, skip: Int = 0, refs: [String]) async throws -> [Commit] {
        let result = try await run(Self.searchLogArguments(query, limit: limit, skip: skip, refs: refs))
        return Self.parseLog(result.stdout)
    }

    /// `git log` arguments for `query`. What the user typed never stands alone in argv,
    /// so it can't be read as an option or a revision:
    /// - message, author and content are glued to their flag (`--grep=<text>`,
    ///   `--author=<text>`, `-S<text>` / `-G<regex>`);
    /// - the path goes after `--`, where git only reads pathspecs.
    ///
    /// `refs` are the app's own revisions (`HistoryScope.revisions`, which include
    /// `--tags`), so `--end-of-options` can't go before them.
    ///
    /// `-i` makes every criterion ignore case: message and author, and content too, since
    /// git applies it to `-S` / `-G` as well. `-F` keeps message and author literal
    /// (`fix(ui)` or `a.b` mean what they say); it doesn't touch `-S`, which is always
    /// literal, or `-G`, which is always an extended regex.
    static func searchLogArguments(_ query: HistorySearchQuery, limit: Int, skip: Int,
                                   refs: [String]) -> [String] {
        let query = query.normalized
        var args = ["log", "--date-order", "--format=\(logFormat)", "-n", String(limit)]
        if skip > 0 {
            args += ["--skip", String(skip)]
        }
        args += ["--regexp-ignore-case", "--fixed-strings"]
        if !query.message.isEmpty {
            args.append("--grep=\(query.message)")
        }
        if !query.author.isEmpty {
            args.append("--author=\(query.author)")
        }
        if !query.content.isEmpty {
            args.append((query.contentIsRegex ? "-G" : "-S") + query.content)
        }
        args += refs
        // Always close the revisions: a ref named like a file can't be read as a path,
        // and without a path the walk isn't limited to one.
        args.append("--")
        if !query.path.isEmpty {
            args.append(query.path)
        }
        return args
    }

    /// Every path in the index, for the path criterion's completion.
    func trackedFiles() async throws -> [String] {
        let result = try await run(["ls-files", "-z", "--"])
        return result.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
    }
}
