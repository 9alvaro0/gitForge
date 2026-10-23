import AppKit
import QuartzCore
import Synchronization

// SCRATCH: G5 cost measurement harness. Never merged.

nonisolated enum G5BenchEnv {
    static let env = ProcessInfo.processInfo.environment
    static var repo: String? { env["GF_BENCH_REPO"] }
    static var isActive: Bool { repo != nil }
    /// Prototype only: compute and play the HEAD-switch animation.
    static var animates: Bool { env["GF_G5_ANIMATE"] != "0" }
    static var scenario: String { env["GF_BENCH_SCENARIO"] ?? "all" }
    static var output: String { env["GF_BENCH_OUT"] ?? "/tmp/g5bench.json" }
    static var branches: [String] { (env["GF_BENCH_BRANCHES"] ?? "main").split(separator: ",").map(String.init) }
    static var warmRows: Int { Int(env["GF_BENCH_WARM_ROWS"] ?? "") ?? 2000 }
    static var label: String { env["GF_BENCH_LABEL"] ?? "unnamed" }
    static var runs: Int { Int(env["GF_BENCH_RUNS"] ?? "") ?? 3 }
    static var speed: Double { Double(env["GF_BENCH_SPEED"] ?? "") ?? 4000 }
}

nonisolated final class G5BenchCounters: Sendable {
    static let shared = G5BenchCounters()
    let canvasRenders = Atomic<Int>(0)
    let canvasNanos = Atomic<Int>(0)
    let motionCanvasRenders = Atomic<Int>(0)
    let applies = Atomic<Int>(0)
    /// CACurrentMediaTime of the last graph apply, in ns.
    let lastApplyNanos = Atomic<Int>(0)
    /// Time spent computing the motion off the main actor, in ns (last one).
    let motionNanos = Atomic<Int>(0)
    let motionRows = Atomic<Int>(0)

    func canvas(started t0: CFTimeInterval, moving: Bool) {
        canvasRenders.add(1, ordering: .relaxed)
        canvasNanos.add(Int((CACurrentMediaTime() - t0) * 1e9), ordering: .relaxed)
        if moving { motionCanvasRenders.add(1, ordering: .relaxed) }
    }

    func applied() {
        applies.add(1, ordering: .relaxed)
        lastApplyNanos.store(Int(CACurrentMediaTime() * 1e9), ordering: .relaxed)
    }

    struct Snapshot {
        let renders: Int, nanos: Int, motionRenders: Int
    }

    func snapshot() -> Snapshot {
        Snapshot(renders: canvasRenders.load(ordering: .relaxed), nanos: canvasNanos.load(ordering: .relaxed),
                 motionRenders: motionCanvasRenders.load(ordering: .relaxed))
    }
}

@MainActor
final class G5FrameRecorder: NSObject {
    private var link: CADisplayLink?
    private(set) var stamps: [CFTimeInterval] = []
    private(set) var durations: [CFTimeInterval] = []
    var onTick: ((CADisplayLink) -> Void)?

    func start(on view: NSView) {
        stamps.removeAll()
        durations.removeAll()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        stamps.append(link.timestamp)
        durations.append(link.targetTimestamp - link.timestamp)
        onTick?(link)
    }

    func stop() {
        link?.invalidate()
        link = nil
        onTick = nil
    }
}

nonisolated struct G5FrameStats: Codable {
    var frames = 0
    var seconds = 0.0
    var nominalMs = 0.0
    var p50Ms = 0.0
    var p95Ms = 0.0
    var maxMs = 0.0
    var hitches = 0
    var hitchMsPerSecond = 0.0
    var canvasRenders = 0
    var canvasMs = 0.0
    var canvasUsPerRender = 0.0
    var motionRenders = 0

    static func make(stamps: [CFTimeInterval], durations: [CFTimeInterval], from: CFTimeInterval, to: CFTimeInterval,
                     before: G5BenchCounters.Snapshot, after: G5BenchCounters.Snapshot) -> G5FrameStats {
        var stats = G5FrameStats()
        let pairs = zip(stamps, stamps.dropFirst()).filter { $0.1 >= from && $0.1 <= to }
        let intervals = pairs.map { $0.1 - $0.0 }.sorted()
        let nominal = durations.sorted().dropFirst(durations.count / 2).first ?? (1.0 / 120)
        stats.frames = intervals.count
        stats.seconds = to - from
        stats.nominalMs = nominal * 1000
        if !intervals.isEmpty {
            stats.p50Ms = intervals[intervals.count / 2] * 1000
            stats.p95Ms = intervals[min(intervals.count - 1, Int(Double(intervals.count) * 0.95))] * 1000
            stats.maxMs = intervals.last! * 1000
            let late = intervals.filter { $0 > 1.5 * nominal }
            stats.hitches = late.count
            stats.hitchMsPerSecond = late.reduce(0) { $0 + ($1 - nominal) } * 1000 / max(stats.seconds, 0.001)
        }
        stats.canvasRenders = after.renders - before.renders
        stats.canvasMs = Double(after.nanos - before.nanos) / 1e6
        stats.canvasUsPerRender = stats.canvasRenders > 0 ? stats.canvasMs * 1000 / Double(stats.canvasRenders) : 0
        stats.motionRenders = after.motionRenders - before.motionRenders
        return stats
    }
}

nonisolated struct G5BenchRecord: Codable {
    var label: String
    var repo: String
    var scenario: String
    var run: Int
    var detail: String
    var latencyMs: Double?
    var motionMs: Double?
    var motionRows: Int?
    var stats: G5FrameStats
}

@MainActor
final class G5BenchRunner {
    private let appState: AppState
    private let recorder = G5FrameRecorder()
    private var records: [G5BenchRecord] = []

    init(appState: AppState) {
        self.appState = appState
    }

    func run() async {
        guard let path = G5BenchEnv.repo else { return }
        // No App Nap or timer coalescing while measuring.
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .latencyCritical],
                                                             reason: "G5 bench")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        do {
            try await appState.openRepository(at: URL(fileURLWithPath: path))
        } catch {
            finish(error: "open failed: \(error)")
            return
        }
        guard let vm = await waitForLog() else { return finish(error: "no log") }
        try? await Task.sleep(for: .seconds(1.5))
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !$0.isSheet }) else {
            return finish(error: "no window")
        }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame.insetBy(dx: 6, dy: 6)
            window.setFrame(frame, display: true)
        }
        // Launched from a shell the app can't take focus; a floating window stays on screen,
        // unoccluded, so it keeps rendering and its display link keeps firing.
        window.level = .floating
        window.orderFrontRegardless()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1))
        let scenario = G5BenchEnv.scenario
        if scenario == "all" || scenario.contains("switch") {
            await switches(vm: vm, window: window, scrolling: false)
        }
        if scenario == "all" || scenario.contains("swscroll") {
            await switches(vm: vm, window: window, scrolling: true)
        }
        if scenario == "all" || scenario.contains("scroll") {
            await warmScroll(vm: vm, window: window)
        }
        finish(error: nil)
    }

    private func waitForLog() async -> RepositoryViewModel? {
        for _ in 0..<600 {
            if let vm = appState.catalog.activeViewModel, !vm.history.commits.isEmpty, !vm.history.isLoadingInitial {
                return vm
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    private func historyScrollView(in window: NSWindow) -> NSScrollView? {
        var found: [NSScrollView] = []
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView { found.append(scroll) }
            view.subviews.forEach(visit)
        }
        if let content = window.contentView { visit(content) }
        return found.max { ($0.documentView?.frame.height ?? 0) < ($1.documentView?.frame.height ?? 0) }
    }

    private func scroll(_ scrollView: NSScrollView, toY y: CGFloat) {
        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: min(max(0, y), maxY)))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Scrolls through rows already loaded, down then up, at a constant speed.
    private func warmScroll(vm: RepositoryViewModel, window: NSWindow) async {
        let target = G5BenchEnv.warmRows
        var guardCount = 0
        while vm.history.commits.count < target, vm.history.hasMore, guardCount < 400 {
            guardCount += 1
            if let last = vm.history.commits.last { await vm.history.loadMoreIfNeeded(currentItem: last) }
            try? await Task.sleep(for: .milliseconds(30))
        }
        guard let scrollView = historyScrollView(in: window) else { return }
        scroll(scrollView, toY: 0)
        try? await Task.sleep(for: .seconds(1.5))
        let rowCount = vm.history.commits.count
        for run in 0..<G5BenchEnv.runs {
            for direction in [1.0, -1.0] {
                let speed = G5BenchEnv.speed
                let duration = 2.5
                let startY = scrollView.contentView.bounds.origin.y
                let before = G5BenchCounters.shared.snapshot()
                var t0: CFTimeInterval?
                recorder.onTick = { [weak self] link in
                    guard let self else { return }
                    let start = t0 ?? link.timestamp
                    t0 = start
                    self.scroll(scrollView, toY: startY + direction * speed * (link.timestamp - start))
                }
                recorder.start(on: window.contentView!)
                try? await Task.sleep(for: .seconds(duration))
                let stamps = recorder.stamps, durations = recorder.durations
                recorder.stop()
                let after = G5BenchCounters.shared.snapshot()
                let from = stamps.first ?? 0
                records.append(G5BenchRecord(
                    label: G5BenchEnv.label, repo: G5BenchEnv.repo ?? "", scenario: "scroll", run: run,
                    detail: direction > 0 ? "down \(rowCount) rows loaded" : "up",
                    latencyMs: nil, motionMs: nil, motionRows: nil,
                    stats: .make(stamps: stamps, durations: durations, from: from + 0.1, to: from + duration,
                                 before: before, after: after)))
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Checks out the branches in turn at the top of the table and records the frames after each switch.
    private func switches(vm: RepositoryViewModel, window: NSWindow, scrolling: Bool) async {
        let names = G5BenchEnv.branches
        guard names.count >= 2, let scrollView = historyScrollView(in: window) else { return }
        scroll(scrollView, toY: 0)
        try? await Task.sleep(for: .seconds(1))
        let total = G5BenchEnv.runs * names.count
        for run in 0..<total {
            let name = names[(run + 1) % names.count]
            guard let ref = vm.refs.first(where: { $0.isLocalBranch && $0.name == name }) else { continue }
            if !scrolling { scroll(scrollView, toY: 0) }
            try? await Task.sleep(for: .seconds(0.8))
            let appliesBefore = G5BenchCounters.shared.applies.load(ordering: .relaxed)
            let before = G5BenchCounters.shared.snapshot()
            var scrollStart: CFTimeInterval?
            let startY = scrollView.contentView.bounds.origin.y
            recorder.onTick = { [weak self] link in
                guard let self, scrolling else { return }
                let applies = G5BenchCounters.shared.applies.load(ordering: .relaxed)
                guard applies > appliesBefore else { return }
                let start = scrollStart ?? link.timestamp
                scrollStart = start
                self.scroll(scrollView, toY: startY + 3000 * (link.timestamp - start))
            }
            recorder.start(on: window.contentView!)
            try? await Task.sleep(for: .milliseconds(100))
            let t0 = CACurrentMediaTime()
            _ = await vm.checkoutBranch(ref)
            let t1 = CACurrentMediaTime()
            try? await Task.sleep(for: .seconds(1.2))
            let stamps = recorder.stamps, durations = recorder.durations
            recorder.stop()
            let after = G5BenchCounters.shared.snapshot()
            // The first apply after the checkout started: the layout with the new HEAD.
            let applyTime = firstApply(after: t0, appliesBefore: appliesBefore)
            let window0 = applyTime ?? t1
            records.append(G5BenchRecord(
                label: G5BenchEnv.label, repo: G5BenchEnv.repo ?? "", scenario: scrolling ? "switch+scroll" : "switch",
                run: run, detail: "to \(name), checkout call \(Int((t1 - t0) * 1000)) ms",
                latencyMs: applyTime.map { ($0 - t0) * 1000 },
                motionMs: Double(G5BenchCounters.shared.motionNanos.load(ordering: .relaxed)) / 1e6,
                motionRows: G5BenchCounters.shared.motionRows.load(ordering: .relaxed),
                stats: .make(stamps: stamps, durations: durations, from: window0, to: window0 + 0.45,
                             before: before, after: after)))
            G5BenchCounters.shared.motionNanos.store(0, ordering: .relaxed)
            G5BenchCounters.shared.motionRows.store(0, ordering: .relaxed)
        }
    }

    /// Apply timestamps are only kept as "last"; the first one after `t0` is recorded by `G5ApplyLog`.
    private func firstApply(after t0: CFTimeInterval, appliesBefore: Int) -> CFTimeInterval? {
        G5ApplyLog.shared.first(after: t0)
    }

    private func finish(error: String?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        struct Output: Codable { let error: String?; let records: [G5BenchRecord] }
        if let data = try? encoder.encode(Output(error: error, records: records)) {
            try? data.write(to: URL(fileURLWithPath: G5BenchEnv.output))
        }
        NSApp.terminate(nil)
    }
}

/// Timestamps of every graph apply, main actor only.
@MainActor
final class G5ApplyLog {
    static let shared = G5ApplyLog()
    private var stamps: [CFTimeInterval] = []

    func record() {
        stamps.append(CACurrentMediaTime())
        G5BenchCounters.shared.applied()
    }

    func first(after t0: CFTimeInterval) -> CFTimeInterval? {
        stamps.first { $0 >= t0 }
    }
}
