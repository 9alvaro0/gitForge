import Foundation
import Testing
@testable import gitForge

@Suite("AutoFetcher — pause / resume", .serialized)
@MainActor
struct AutoFetcherPauseResumeTests {

    @Test("pause() cancels the loop but keeps interval + closure")
    func pausePreservesConfig() async {
        let fetcher = AutoFetcher()
        let counter = AsyncCounter()
        fetcher.start(intervalSeconds: 60) { await counter.bump() }
        #expect(fetcher.intervalSeconds == 60)

        fetcher.pause()
        // Pause keeps the interval so resume can use it without the caller
        // re-supplying the closure. Distinguishes pause from stop.
        #expect(fetcher.intervalSeconds == 60)
    }

    @Test("stop() clears the interval and the closure")
    func stopClearsConfig() async {
        let fetcher = AutoFetcher()
        let counter = AsyncCounter()
        fetcher.start(intervalSeconds: 30) { await counter.bump() }
        fetcher.stop()
        #expect(fetcher.intervalSeconds == 0)

        // After stop, resume must be a no-op — there's no closure left.
        fetcher.resume()
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await counter.value == 0)
    }

    @Test("resume() after pause re-schedules the loop")
    func resumeAfterPauseSchedulesAgain() async {
        // Use a very small interval so the loop ticks within the test window.
        // The closure increments a counter so we can assert it ran.
        let fetcher = AutoFetcher()
        let counter = AsyncCounter()

        // Configure but immediately pause so we control when the loop fires.
        fetcher.start(intervalSeconds: 1) { await counter.bump() }
        fetcher.pause()
        let beforeResume = await counter.value
        #expect(beforeResume == 0)

        fetcher.resume()
        // Wait long enough for one tick at interval=1s.
        try? await Task.sleep(for: .seconds(1) + .milliseconds(300))
        let afterResume = await counter.value
        #expect(afterResume >= 1)

        // Clean up so the loop doesn't leak past the test.
        fetcher.stop()
    }

    @Test("resume() when never started is a no-op")
    func resumeBeforeStartIsNoOp() async {
        let fetcher = AutoFetcher()
        fetcher.resume()
        #expect(fetcher.intervalSeconds == 0)
    }
}

private actor AsyncCounter {
    private(set) var value = 0
    func bump() { value += 1 }
}
