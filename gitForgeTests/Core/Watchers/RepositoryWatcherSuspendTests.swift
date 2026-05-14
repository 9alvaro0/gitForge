import Foundation
import Testing
@testable import gitForge

@Suite("RepositoryWatcher — suspend / resume", .serialized)
@MainActor
struct RepositoryWatcherSuspendTests {

    private func makeRepoDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitForge-watcher-\(UUID().uuidString)")
        // `.git/HEAD` etc. need to exist so the watcher's open(O_EVTONLY)
        // calls succeed; otherwise the watch points silently no-op and these
        // tests pass for the wrong reason.
        let gitDir = url.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("refs/heads"),
                                                 withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("refs/remotes"),
                                                 withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("refs/tags"),
                                                 withIntermediateDirectories: true)
        try Data().write(to: gitDir.appendingPathComponent("HEAD"))
        try Data().write(to: gitDir.appendingPathComponent("packed-refs"))
        return url
    }

    @Test("Default state: a forced poke invokes onChange")
    func defaultAllowsPoke() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        watcher.poke(force: true)
        // Forced pokes use delay=0 but still schedule on the run loop;
        // yield enough for the Task to run.
        try await Task.sleep(for: .milliseconds(100))
        #expect(await counter.value == 1)
        _ = watcher
    }

    @Test("After suspend, a forced poke is dropped")
    func suspendBlocksPoke() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        watcher.suspend()
        watcher.poke(force: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await counter.value == 0)
        _ = watcher
    }

    @Test("After resume, a forced poke fires again")
    func resumeReEnablesPoke() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        watcher.suspend()
        watcher.resume()
        watcher.poke(force: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await counter.value == 1)
        _ = watcher
    }

    @Test("Suspend cancels any pending refresh task scheduled before it")
    func suspendCancelsPending() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        // Non-forced poke goes through the 1s debounce — cancel it before it
        // fires by suspending.
        watcher.poke(force: false)
        watcher.suspend()
        try await Task.sleep(for: .milliseconds(1200))
        #expect(await counter.value == 0)
        _ = watcher
    }

    @Test("A second poke inside the cooldown defers instead of being dropped")
    func cooldownDeferDoesntDropEvent() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        // Forced poke runs immediately and sets `lastRefresh = now`.
        watcher.poke(force: true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(await counter.value == 1)

        // Within the 1.5s cooldown, a non-forced poke previously DROPPED the
        // event. It must defer until the cooldown elapses and then fire,
        // not vanish.
        watcher.poke(force: false)
        try await Task.sleep(for: .milliseconds(200))
        // Cooldown hasn't elapsed yet — refresh shouldn't have fired again.
        #expect(await counter.value == 1)

        // After the cooldown window passes the deferred refresh should fire.
        try await Task.sleep(for: .seconds(2))
        #expect(await counter.value == 2)
        _ = watcher
    }
}

/// Tiny actor-as-counter so concurrent main-actor closures can write safely
/// without each test rolling its own synchronisation.
private actor ChangeCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
