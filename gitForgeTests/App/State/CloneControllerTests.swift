import Foundation
import Testing
@testable import gitForge

@Suite("CloneController — waiting for a clone")
@MainActor
struct CloneControllerTests {

    @MainActor
    final class Log {
        var entries: [String] = []
    }

    @Test("finished returns at once when no clone is running")
    func finishedWithNothingRunning() async {
        await CloneController().finished()
    }

    @Test("finished returns only once the running clone's work has ended")
    func finishedWaitsForTheWork() async {
        let controller = CloneController()
        let gate = AsyncGate()
        let log = Log()
        controller.start {
            await gate.wait()
            log.entries.append("work")
        }
        await gate.waiting()
        let waiter = Task { @MainActor in
            await controller.finished()
            log.entries.append("finished")
        }
        gate.open()
        await waiter.value
        #expect(log.entries == ["work", "finished"])
    }
}
