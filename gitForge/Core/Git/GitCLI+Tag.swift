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

    /// `git push origin <name>` — single tag.
    func pushTag(name: String, remote: String = "origin") async throws {
        _ = try await run(["push", Self.endOfOptions, remote, name])
    }

    /// `git push origin --delete <name>` — removes the tag from the remote.
    func pushDeleteTag(name: String, remote: String = "origin") async throws {
        _ = try await run(["push", "--delete", Self.endOfOptions, remote, name])
    }

    /// `git push --tags` — pushes every annotated tag the remote doesn't have.
    func pushAllTags(remote: String = "origin") async throws {
        _ = try await run(["push", "--tags", Self.endOfOptions, remote])
    }
}
