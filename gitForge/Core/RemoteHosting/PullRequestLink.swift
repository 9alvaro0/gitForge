import Foundation

/// A pull/merge request's web URL on a declared instance (spec §4.4).
nonisolated struct PullRequestLink: Hashable, Sendable {
    let host: RemoteHost
    let number: Int
    let instanceId: UUID

    /// The link in `text` when its host is a declared instance of the kind the
    /// URL's shape belongs to: `/<group>/…/<repo>/-/merge_requests/<N>` (or the
    /// older `/merge_requests/<N>`) on GitLab, `/<owner>/<repo>/pull/<N>` on
    /// GitHub. Whatever follows the number (`/diffs`, a query, a fragment) is
    /// ignored; one provider's shape on the other's instance isn't a link.
    static func parse(_ text: String, instances: [HostingInstance]) -> PullRequestLink? {
        guard let shape = Shape.read(text),
              let instance = instances.first(where: { $0.host == shape.host }),
              instance.kind == shape.kind,
              let host = RemoteHost.make(fullName: shape.repoPath, on: instance) else { return nil }
        return PullRequestLink(host: host, number: shape.number, instanceId: instance.id)
    }

    /// A link on a host that isn't declared, offered as "Add <host> as a
    /// <kind> instance…". The kind comes from the URL's shape, not from the
    /// host's name: a self-hosted GitLab can be called anything.
    static func suggestion(for text: String, instances: [HostingInstance]) -> InstanceSuggestion? {
        guard let shape = Shape.read(text),
              !instances.contains(where: { $0.host == shape.host }) else { return nil }
        return InstanceSuggestion(host: shape.host, kind: shape.kind)
    }

    /// What a URL says before any instance is consulted.
    private struct Shape {
        let host: String
        let kind: HostingInstance.Kind
        let repoPath: String
        let number: Int

        static func read(_ text: String) -> Shape? {
            guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let rawHost = components.host, let host = HostingInstance.normalizedHost(rawHost) else { return nil }
            let segments = components.path.split(separator: "/").map(String.init)
            if let (repoPath, number) = gitlabForm(segments) {
                return Shape(host: host, kind: .gitlab, repoPath: repoPath, number: number)
            }
            if let (repoPath, number) = githubForm(segments) {
                return Shape(host: host, kind: .github, repoPath: repoPath, number: number)
            }
            return nil
        }

        /// `…/<repo>/-/merge_requests/<N>` or the older `…/<repo>/merge_requests/<N>`.
        /// A `-` left before it ends the repo earlier: the path goes on into
        /// the repo (`/-/blob/main/merge_requests/5`), not to a merge request.
        private static func gitlabForm(_ segments: [String]) -> (repoPath: String, number: Int)? {
            for index in segments.indices.dropLast() where segments[index] == "merge_requests" {
                guard let number = number(segments[index + 1]) else { continue }
                var repo = segments[..<index]
                if repo.last == "-" { repo.removeLast() }
                guard !repo.contains("-") else { return nil }
                return (repo.joined(separator: "/"), number)
            }
            return nil
        }

        /// `<owner>/<repo>/pull/<N>`.
        private static func githubForm(_ segments: [String]) -> (repoPath: String, number: Int)? {
            guard segments.count >= 4, segments[2] == "pull", let number = number(segments[3]) else { return nil }
            return (segments[..<2].joined(separator: "/"), number)
        }

        /// A whole-digit segment above zero.
        private static func number(_ segment: String) -> Int? {
            guard segment.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(segment), value > 0 else { return nil }
            return value
        }
    }
}
