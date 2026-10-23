import Foundation

extension GitCLI {
    /// Local branches, remote branches and, with `includingTags`, tags. Without
    /// them the read skips what makes it slow in a repo with thousands of tags
    /// (each one's subject, peeled): the history's first page only needs the
    /// branches.
    func refs(includingTags: Bool = true) async throws -> [GitRef] {
        // %(*objectname) is the dereferenced commit for annotated tags; empty for
        // everything else. We prefer it over %(objectname) (which would be the tag
        // OBJECT, not the commit, for annotated tags).
        // Upstream, track, date and subject feed the Branches table; the
        // subject goes last so a tab inside it can't shift the columns.
        let format = "%(objectname)%09%(*objectname)%09%(refname)%09%(HEAD)%09%(upstream:short)%09%(upstream:track)%09%(creatordate:unix)%09%(contents:subject)"
        let patterns = ["refs/heads", "refs/remotes"] + (includingTags ? ["refs/tags"] : [])
        let result = try await run(["for-each-ref", "--format=\(format)"] + patterns)
        return Self.parseRefs(result.stdout)
    }

    /// Branch each remote's HEAD points at, by remote: ["origin": "origin/main"]. Remotes
    /// without a HEAD are left out. Picks the remote trunk (`GraphTrunks.remoteStandIns`).
    func remoteHeads() async throws -> [String: String] {
        let result = try await run(["for-each-ref", "--format=%(refname)%09%(symref)", "refs/remotes"])
        return Self.parseRemoteHeads(result.stdout)
    }

    /// `refname<TAB>symref` lines: only `refs/remotes/<remote>/HEAD` symrefs count.
    static func parseRemoteHeads(_ stdout: String) -> [String: String] {
        var heads: [String: String] = [:]
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 2,
                  let ref = String(parts[0]).removingPrefix("refs/remotes/"),
                  ref.hasSuffix("/HEAD"),
                  let target = String(parts[1]).removingPrefix("refs/remotes/")
            else { continue }
            heads[String(ref.dropLast("/HEAD".count))] = target
        }
        return heads
    }

    /// The branch HEAD is on (unborn included), or `.detached`. Throws when
    /// the read itself fails, so a caller can tell "no branch" from "couldn't
    /// tell".
    func headBranch() async throws -> HeadBranch {
        let args = ["symbolic-ref", "--quiet", "--short", "HEAD"]
        let result: GitResult
        do {
            result = try await run(args)
        } catch GitError.commandFailed(_, 1, _) {
            // With `--quiet`, exit 1 means "HEAD is not a symbolic ref";
            // real failures exit 128.
            return .detached
        }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitError.commandFailed(args: args, exitCode: result.exitCode, stderr: result.stderr)
        }
        return .branch(trimmed)
    }

    /// `nil` when detached or when the read fails.
    func currentBranchName() async -> String? {
        try? await headBranch().name
    }

    /// The commit HEAD points at, branch or detached; `nil` in an empty repo.
    func headSha() async -> String? {
        guard let result = try? await run(["rev-parse", "--verify", "--quiet", "HEAD"]) else { return nil }
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func parseRefs(_ stdout: String) -> [GitRef] {
        stdout.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { return nil }
            let directSha = String(parts[0])
            let dereferencedSha = String(parts[1])
            let refname = String(parts[2])
            let isHead = parts.count >= 4 && String(parts[3]) == "*"
            let upstream = parts.count >= 5 && !parts[4].isEmpty ? String(parts[4]) : nil
            let track = parts.count >= 6 ? UpstreamTrack.parse(String(parts[5])) : UpstreamTrack()
            let date = parts.count >= 7 ? TimeInterval(String(parts[6])).map { Date(timeIntervalSince1970: $0) } : nil
            let subject = parts.count >= 8 ? parts[7...].joined(separator: "\t") : nil

            // Use dereferenced SHA when present (annotated tags); fall back to the direct SHA.
            let commitSha = dereferencedSha.isEmpty ? directSha : dereferencedSha

            if let local = refname.removingPrefix("refs/heads/") {
                return GitRef(
                    name: local, kind: .localBranch, targetSha: commitSha, isHead: isHead,
                    upstream: upstream,
                    ahead: upstream == nil ? nil : track.ahead,
                    behind: upstream == nil ? nil : track.behind,
                    upstreamGone: track.gone,
                    subject: subject, date: date
                )
            }
            if let remoteFull = refname.removingPrefix("refs/remotes/") {
                if remoteFull == "origin/HEAD" || remoteFull.hasSuffix("/HEAD") {
                    return nil // skip remote HEAD pointers
                }
                let remote = remoteFull.split(separator: "/").first.map(String.init) ?? ""
                return GitRef(name: remoteFull, kind: .remoteBranch(remote: remote), targetSha: commitSha, isHead: false,
                              subject: subject, date: date)
            }
            if let tag = refname.removingPrefix("refs/tags/") {
                return GitRef(name: tag, kind: .tag, targetSha: commitSha, isHead: false,
                              subject: subject, date: date)
            }
            return nil
        }
    }
}

/// What `.git/HEAD` points at.
nonisolated enum HeadBranch: Sendable, Equatable {
    case branch(String)
    case detached

    /// The branch name; `nil` when detached.
    var name: String? {
        if case .branch(let name) = self { return name }
        return nil
    }
}

private extension String {
    nonisolated func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
