import Foundation

extension GitCLI {
    /// Creates a tag. Pass `message: nil` for a lightweight tag,
    /// non-nil for an annotated tag (`-a`).
    func createTag(name: String, at sha: String? = nil, message: String? = nil) async throws {
        var args: [String] = ["tag"]
        if let message { args += ["-a", "-m", message] }
        args.append(Self.endOfOptions)
        args.append(name)
        if let sha { args.append(sha) }
        _ = try await run(args)
    }

    func deleteTag(name: String) async throws {
        _ = try await run(["tag", "-d", Self.endOfOptions, name])
    }

    /// `git push <remote> refs/tags/<name>` — single tag. Fully qualified
    /// so a branch with the same name can't make the refspec ambiguous.
    func pushTag(name: String, remote: String = "origin") async throws {
        _ = try await run(["push", Self.endOfOptions, remote, Self.tagRef(name)])
    }

    /// `git push <remote> --delete refs/tags/<name>`. Fully qualified: with a
    /// bare name, a remote that has a *branch* called `<name>` (and no such
    /// tag) would have that branch deleted instead.
    func pushDeleteTag(name: String, remote: String = "origin") async throws {
        _ = try await run(["push", "--delete", Self.endOfOptions, remote, Self.tagRef(name)])
    }

    /// `git push --tags` — pushes every tag under `refs/tags/` (lightweight
    /// and annotated) that the remote doesn't have yet.
    func pushAllTags(remote: String = "origin") async throws {
        _ = try await run(["push", "--tags", Self.endOfOptions, remote])
    }

    static func tagRef(_ name: String) -> String {
        name.hasPrefix("refs/tags/") ? name : "refs/tags/\(name)"
    }
}
