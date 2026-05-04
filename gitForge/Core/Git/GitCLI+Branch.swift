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
