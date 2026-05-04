import Foundation

extension GitCLI {
    func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["add", "--"] + paths)
    }

    func unstage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["restore", "--staged", "--"] + paths)
    }

    func discardChanges(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await run(["restore", "--"] + paths)
    }

    /// Removes untracked files from the working copy.
    func deleteUntracked(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let fm = FileManager.default
        let base = workingDirectory.path(percentEncoded: false)
        for path in paths {
            let full = (base as NSString).appendingPathComponent(path)
            try? fm.removeItem(atPath: full)
        }
    }

    func commit(subject: String, body: String? = nil, amend: Bool = false) async throws {
        var args: [String] = ["commit"]
        if amend { args.append("--amend") }
        args.append("-m")
        args.append(subject)
        if let body, !body.isEmpty {
            args.append("-m")
            args.append(body)
        }
        try await run(args)
    }
}
