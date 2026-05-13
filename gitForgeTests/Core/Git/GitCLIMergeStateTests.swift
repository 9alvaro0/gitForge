import Foundation
import Testing
@testable import gitForge

@Suite("GitCLI.mergeState — marker detection", .serialized)
struct GitCLIMergeStateTests {

    private func makeRepoDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-mergestate-\(UUID().uuidString)")
        let gitDir = url.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        return url
    }

    private func placeMarker(_ name: String, in repo: URL, asDirectory: Bool = false) throws {
        let target = repo.appendingPathComponent(".git").appendingPathComponent(name)
        if asDirectory {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } else {
            try Data().write(to: target)
        }
    }

    @Test("MERGE_HEAD marker → .merging")
    func detectsMerging() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try placeMarker("MERGE_HEAD", in: dir)
        let cli = GitCLI(workingDirectory: dir)
        // unmergedPaths() throws on a non-initialised .git dir; we only care
        // about the marker-file branch here, which runs before the cli call.
        let state = await cli.mergeState()
        #expect(state == .merging)
    }

    @Test("rebase-merge directory → .rebasing")
    func detectsRebasingMerge() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try placeMarker("rebase-merge", in: dir, asDirectory: true)
        let cli = GitCLI(workingDirectory: dir)
        let state = await cli.mergeState()
        #expect(state == .rebasing)
    }

    @Test("rebase-apply directory → .rebasing (am / format-patch flow)")
    func detectsRebasingApply() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try placeMarker("rebase-apply", in: dir, asDirectory: true)
        let cli = GitCLI(workingDirectory: dir)
        let state = await cli.mergeState()
        #expect(state == .rebasing)
    }

    @Test("CHERRY_PICK_HEAD marker → .cherryPicking")
    func detectsCherryPicking() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try placeMarker("CHERRY_PICK_HEAD", in: dir)
        let cli = GitCLI(workingDirectory: dir)
        let state = await cli.mergeState()
        #expect(state == .cherryPicking)
    }

    @Test("REVERT_HEAD marker → .reverting")
    func detectsReverting() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try placeMarker("REVERT_HEAD", in: dir)
        let cli = GitCLI(workingDirectory: dir)
        let state = await cli.mergeState()
        #expect(state == .reverting)
    }

    @Test("BISECT_LOG marker → .bisecting")
    func detectsBisecting() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try placeMarker("BISECT_LOG", in: dir)
        let cli = GitCLI(workingDirectory: dir)
        let state = await cli.mergeState()
        #expect(state == .bisecting)
    }

    @Test("MERGE_HEAD wins over CHERRY_PICK_HEAD when both are present")
    func mergeBeatsCherryPick() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // Pathological state, but resolution order matters: the marker that
        // owns the resolve command (`git merge --continue` vs cherry-pick's)
        // must win. We prioritise MERGE_HEAD because that's what `git`
        // itself prioritises in its own state machine.
        try placeMarker("MERGE_HEAD", in: dir)
        try placeMarker("CHERRY_PICK_HEAD", in: dir)
        let cli = GitCLI(workingDirectory: dir)
        let state = await cli.mergeState()
        #expect(state == .merging)
    }

    @Test("isInProgress is true for every non-clean state")
    func isInProgressMatrix() {
        #expect(MergeState.clean.isInProgress == false)
        #expect(MergeState.merging.isInProgress == true)
        #expect(MergeState.rebasing.isInProgress == true)
        #expect(MergeState.cherryPicking.isInProgress == true)
        #expect(MergeState.reverting.isInProgress == true)
        #expect(MergeState.bisecting.isInProgress == true)
        #expect(MergeState.unmerged.isInProgress == true)
    }
}
