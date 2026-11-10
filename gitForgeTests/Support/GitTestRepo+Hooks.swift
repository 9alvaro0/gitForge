import Foundation

extension GitTestRepo {
    /// Installs `script` as hook `name`, in a hooks folder outside the
    /// worktree (so it never shows up as an untracked file) set as this
    /// repo's `core.hooksPath`. Repo-local config wins over a developer's
    /// global `core.hooksPath`, so `GitCLI` — which runs with the normal
    /// config — runs exactly these hooks. `executable: false` leaves the
    /// file without the x bit, which git ignores.
    @available(*, noasync, message: "Blocks on git; use installHookAsync from async code")
    func installHook(_ name: String, script: String, executable: Bool = true) throws {
        let hooks = hooksDirectory
        try FileManager.default.createDirectory(at: hooks, withIntermediateDirectories: true)
        let file = hooks.appendingPathComponent(name)
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: executable ? 0o755 : 0o644],
                                              ofItemAtPath: file.path(percentEncoded: false))
        try git("config", "core.hooksPath", hooks.path(percentEncoded: false))
    }

    /// `installHook(_:script:executable:)` on a GCD thread.
    func installHookAsync(_ name: String, script: String, executable: Bool = true) async throws {
        try await perform { try $0.installHook(name, script: script, executable: executable) }
    }

    /// Sibling of the worktree, removed at exit with the other temp folders.
    private var hooksDirectory: URL {
        let url = url.deletingLastPathComponent().appendingPathComponent(url.lastPathComponent + "-hooks")
        TemporaryDirectories.register(url)
        return url
    }
}
