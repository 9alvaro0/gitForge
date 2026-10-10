import Foundation

extension GitCLI {
    func refs() async throws -> [GitRef] {
        // %(*objectname) is the dereferenced commit for annotated tags; empty for
        // everything else. We prefer it over %(objectname) (which would be the tag
        // OBJECT, not the commit, for annotated tags).
        // Upstream, track, date and subject feed the Branches table; the
        // subject goes last so a tab inside it can't shift the columns.
        let format = "%(objectname)%09%(*objectname)%09%(refname)%09%(HEAD)%09%(upstream:short)%09%(upstream:track)%09%(creatordate:unix)%09%(contents:subject)"
        let result = try await run(["for-each-ref", "--format=\(format)", "refs/heads", "refs/remotes", "refs/tags"])
        return Self.parseRefs(result.stdout)
    }

    func currentBranchName() async -> String? {
        do {
            let result = try await run(["symbolic-ref", "--short", "HEAD"])
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
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

private extension String {
    nonisolated func removingPrefix(_ prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }
}
