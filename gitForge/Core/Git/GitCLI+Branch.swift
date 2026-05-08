import Foundation

extension GitCLI {
    func createBranch(_ name: String, startingAt: String? = nil, checkout: Bool = false) async throws {
        var args: [String] = ["branch", name]
        if let startingAt { args.append(startingAt) }
        try await run(args)
        if checkout {
            try await self.checkout(branch: name)
        }
    }

    func checkout(branch: String) async throws {
        try await run(["checkout", branch])
    }

    func deleteBranch(_ name: String, force: Bool = false) async throws {
        try await run(["branch", force ? "-D" : "-d", name])
    }

    func renameBranch(from oldName: String, to newName: String) async throws {
        try await run(["branch", "-m", oldName, newName])
    }

    /// `git branch -f <name> <sha>` — force-updates a local branch tip.
    /// Git refuses to touch the currently checked-out branch this way; route
    /// HEAD moves through `reset(to:mode:)` instead.
    func forceUpdateBranch(_ name: String, to sha: String) async throws {
        try await run(["branch", "-f", name, sha])
    }

    /// Local branch full ref-names (e.g. `refs/heads/develop`) whose tip is
    /// **not** reachable from HEAD. Used as the explicit ref scope for the
    /// graph log: branches already merged into HEAD don't need to be tips in
    /// the walk — their commits arrive through HEAD's merge ancestry, with no
    /// extra column allocated. Returns empty array if HEAD is unborn.
    func unmergedLocalBranches() async throws -> [String] {
        let result = try await run([
            "for-each-ref",
            "--no-merged", "HEAD",
            "--format=%(refname)",
            "refs/heads/"
        ])
        return result.stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }
}

enum BranchValidator {
    /// Lightweight client-side validation; git itself enforces stricter rules.
    static func isValidName(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains(" ") else { return false }
        guard !trimmed.hasPrefix(".") else { return false }
        guard !trimmed.hasSuffix("/") else { return false }
        guard !trimmed.contains("..") else { return false }
        let invalidCharacters: Set<Character> = ["~", "^", ":", "?", "*", "[", "\\"]
        return !trimmed.contains(where: invalidCharacters.contains)
    }
}
