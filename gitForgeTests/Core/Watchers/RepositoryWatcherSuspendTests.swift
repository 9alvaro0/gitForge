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

    @Test("Suspend defers events instead of firing")
    func suspendDoesNotFireImmediately() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        watcher.suspend()
        watcher.poke(force: true)
        try await Task.sleep(for: .milliseconds(150))
        // Still suspended → no refresh has run yet.
        #expect(await counter.value == 0)
        _ = watcher
    }

    @Test("Resume replays a single deferred event")
    func resumeReplaysDeferredEvent() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        watcher.suspend()
        // An external event lands while we're in the middle of a mutation.
        // Without deferral this used to vanish; now it's marked and the
        // resume() call below should fire one refresh.
        watcher.poke(force: false)
        watcher.resume()
        // Resume schedules through the normal (debounced) path, so wait
        // past the 300ms debounce.
        try await Task.sleep(for: .milliseconds(500))
        #expect(await counter.value == 1)
        _ = watcher
    }

    @Test("Multiple events during suspend collapse to one refresh on resume")
    func multipleSuspendedEventsCollapse() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        watcher.suspend()
        watcher.poke(force: false)
        watcher.poke(force: false)
        watcher.poke(force: false)
        watcher.resume()
        try await Task.sleep(for: .milliseconds(500))
        // Three events during suspend, one refresh after resume — the
        // refresh reads fresh state anyway, so a single replay is correct.
        #expect(await counter.value == 1)
        _ = watcher
    }

    @Test("Resume with no deferred event does NOT fire")
    func resumeWithoutEventDoesNotFire() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        // Spurious suspend/resume pair (e.g. an isMutating flip with no real
        // external activity in between) must not generate phantom refreshes.
        watcher.suspend()
        watcher.resume()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await counter.value == 0)
        _ = watcher
    }

    @Test("Resume re-enables forced poke")
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
        // Non-forced poke goes through the 300ms debounce — cancel it before
        // it fires by suspending.
        watcher.poke(force: false)
        watcher.suspend()
        try await Task.sleep(for: .milliseconds(500))
        #expect(await counter.value == 0)
        _ = watcher
    }

    @Test("Back-to-back unforced pokes fire after a single debounce window")
    func debouncedPokeFiresOnce() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            await counter.bump()
        }
        watcher.poke(force: false)
        // Within the 300ms debounce, a follow-up poke should cancel-and-
        // reschedule (not stack). Result: exactly one refresh after the
        // window closes.
        try await Task.sleep(for: .milliseconds(100))
        watcher.poke(force: false)
        try await Task.sleep(for: .milliseconds(500))
        #expect(await counter.value == 1)
        _ = watcher
    }

    @Test("A second event while a refresh is in flight schedules a follow-up")
    func midRefreshEventReschedules() async throws {
        let dir = try makeRepoDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let counter = ChangeCounter()
        // Slow onChange so the second poke lands while the first refresh
        // is still awaiting. The watcher should mark refreshDirty and
        // schedule a follow-up on completion.
        let watcher = RepositoryWatcher(repository: dir) { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            await counter.bump()
        }
        watcher.poke(force: true)
        try await Task.sleep(for: .milliseconds(50))
        watcher.poke(force: false)
        try await Task.sleep(for: .seconds(1))
        // First refresh ran (forced), then the dirty bit fired a second.
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
