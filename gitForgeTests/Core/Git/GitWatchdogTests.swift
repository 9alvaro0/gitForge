import Foundation
import Testing
@testable import gitForge

/// The watchdog's `timedOut` flag is what lets `run` / `clone` report a
/// stalled command as a network timeout instead of a user cancellation.
@Suite("GitWatchdog")
struct GitWatchdogTests {

    private static let logger = GitCLI.logger

    private func sleepProcess() throws -> (Process, ProcessExit) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["30"]
        return (process, try GitProcess.start(process))
    }

    @Test("Kills an idle process and reports timedOut")
    func killsIdleProcess() async throws {
        let (process, exit) = try sleepProcess()
        let watchdog = GitWatchdog(timeout: 0.2, pollInterval: .milliseconds(50))
        watchdog.start(watching: process, label: "sleep", logger: Self.logger)
        defer { watchdog.stop() }

        await exit.wait()
        #expect(watchdog.timedOut)
        #expect(process.terminationReason == .uncaughtSignal)
    }

    @Test("A process terminated by someone else is not reported as timedOut")
    func externalTerminationIsNotTimeout() async throws {
        let (process, exit) = try sleepProcess()
        let watchdog = GitWatchdog(timeout: 60, pollInterval: .milliseconds(50))
        watchdog.start(watching: process, label: "sleep", logger: Self.logger)
        defer { watchdog.stop() }

        process.terminate()
        await exit.wait()
        #expect(!watchdog.timedOut)
    }

    @Test("Timeout message routes to the network failure bucket")
    func timeoutMessageIsNetwork() {
        let watchdog = GitWatchdog(timeout: 30)
        #expect(RemoteFailure(stderr: watchdog.timeoutMessage) == .network)
    }

    @Test("ProcessExit resumes waiters whether the exit lands before or after wait()")
    func processExitOrdering() async throws {
        let fast = Process()
        fast.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let exit = try GitProcess.start(fast)
        try await Task.sleep(for: .milliseconds(200)) // exit most likely already signalled
        await exit.wait()
        #expect(fast.terminationStatus == 0)

        #expect(await GitProcess.runTool("/usr/bin/false", arguments: []) == 1)
        #expect(await GitProcess.runTool("/nonexistent/tool", arguments: []) == nil)
    }
}
