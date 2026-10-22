import AppKit
import SwiftUI
import Testing
@testable import gitForge

/// Hosts `CommitRowList` in a real window, inside a `ScrollView` and a
/// `LazyVStack` like the History table, and records what each row's `Canvas`
/// last drew. A row whose canvas never redraws keeps its old entry.
@Suite("History table — commit row identity", .serialized)
@MainActor
struct CommitRowListTests {

    /// What each row's canvas drew last, by sha. Canvases draw off the main actor.
    nonisolated final class DrawLog: @unchecked Sendable {
        private let lock = NSLock()
        private var drawn: [String: String] = [:]
        func record(_ sha: String, _ tag: String) { lock.withLock { drawn[sha] = tag } }
        var snapshot: [String: String] { lock.withLock { drawn } }
    }

    /// Stands in for `CommitRow`: equatable over its data like the real row,
    /// with a canvas that logs the tag it drew for its commit.
    private struct ProbeRow: View, Equatable {
        static func == (lhs: ProbeRow, rhs: ProbeRow) -> Bool { lhs.sha == rhs.sha && lhs.tag == rhs.tag }
        let sha: String
        let tag: String
        let log: DrawLog

        var body: some View {
            let sha = sha
            let tag = tag
            let log = log
            Canvas { context, size in
                log.record(sha, tag)
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.gray))
            }
            .frame(height: 20)
        }
    }

    private struct Table: View {
        let commits: [Commit]
        /// Stands in for `graphLayouts`: what the row at each index draws.
        let tags: [String]
        let log: DrawLog
        var onLastRowAppear: ((Commit) -> Void)? = nil
        /// Stands in for `HistoryStore.logRevision`.
        var revision: UInt64 = 0
        /// Builds every row, and what follows them, up front. On macOS 26 the lazy
        /// stack builds rows ahead of the scroll in idle time (idle prefetch), which
        /// a test host doesn't do; an eager stack stands in for it.
        var eager = false
        /// Rows wider than the window, so the table scrolls sideways too, like
        /// History with many lanes.
        var wide = false

        var body: some View {
            ScrollView(wide ? [.vertical, .horizontal] : .vertical) {
                stack
                    .frame(width: wide ? 600 : nil)
            }
        }

        @ViewBuilder private var stack: some View {
            if eager {
                VStack(spacing: HistoryTableLayout.rowSpacing) { rows }
            } else {
                LazyVStack(spacing: HistoryTableLayout.rowSpacing) { rows }
            }
        }

        private var rows: some View {
            CommitRowList(commits: commits, revision: revision, onLastRowAppear: onLastRowAppear) { index, commit in
                ProbeRow(sha: commit.sha, tag: tags[safe: index] ?? "none", log: log)
                    .equatable()
            }
        }
    }

    /// A window, by default big enough to show every row, rendered without being shown.
    @MainActor private final class Host {
        let window: NSWindow
        let view: NSHostingView<Table>

        init(_ table: Table, height: CGFloat = 600, until condition: () -> Bool) {
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            view = NSHostingView(rootView: table)
            window.contentView = view
            settle(until: condition)
        }

        func show(_ table: Table, until condition: () -> Bool) {
            view.rootView = table
            settle(until: condition)
        }

        /// Scrolls the table to the bottom of its content, as the user would.
        func scrollToEnd(until condition: () -> Bool) {
            guard let scrollView = Self.scrollView(in: view), let document = scrollView.documentView else { return }
            let clip = scrollView.contentView
            let bottom = document.isFlipped ? document.bounds.maxY - clip.bounds.height : document.bounds.minY
            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: bottom))
            scrollView.reflectScrolledClipView(clip)
            settle(until: condition)
        }

        private static func scrollView(in view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView { return scrollView }
            return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }

        /// Lays out and draws again, in short run-loop slices, until `condition`
        /// has held on two passes in a row (a state that flaps does not count) or
        /// two seconds have gone by. It does not fail on a timeout: the caller's
        /// own assertion then reports what is missing. A slow machine gets the
        /// time it needs and a fast one does not wait for a fixed number of passes.
        private func settle(until condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            var passesHolding = 0
            while passesHolding < 2, Date() < deadline {
                view.layoutSubtreeIfNeeded()
                window.display()
                passesHolding = condition() ? passesHolding + 1 : 0
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
        }
    }

    private static func commits(_ shas: [String]) -> [Commit] {
        shas.map { GraphFixture.commit($0, parents: []) }
    }

    /// `c0` … `c<count - 1>`.
    private static func log(_ count: Int) -> [Commit] {
        commits((0..<count).map { "c\($0)" })
    }

    /// Room for about nine rows: shorter than `log(15)`, whose end the lazy
    /// stack still builds ahead of the scroll.
    private static let shortViewport: CGFloat = 200

    @Test("A reload that moves commits to new rows redraws every row with its new data")
    func rowsFollowAShift() {
        let log = DrawLog()
        let initial = ["a": "a0", "b": "b0", "c": "c0"]
        let host = Host(Table(commits: Self.commits(["a", "b", "c"]), tags: ["a0", "b0", "c0"], log: log),
                        until: { log.snapshot == initial })
        #expect(log.snapshot == initial)

        // `replaceLog` lands first, with the graph of the old log still in place.
        let shifted = Self.commits(["s", "a", "b", "c"])
        let staleGraph = ["s": "a0", "a": "b0", "b": "c0", "c": "none"]
        host.show(Table(commits: shifted, tags: ["a0", "b0", "c0"], log: log), until: { log.snapshot == staleGraph })
        #expect(log.snapshot == staleGraph)

        // Then the recomputed graph.
        let recomputed = ["s": "s1", "a": "a1", "b": "b1", "c": "c1"]
        host.show(Table(commits: shifted, tags: ["s1", "a1", "b1", "c1"], log: log), until: { log.snapshot == recomputed })
        #expect(log.snapshot == recomputed)

        // Dropping the top row shifts everything back up.
        let shiftedBack = { log.snapshot["a"] == "a2" && log.snapshot["b"] == "b2" && log.snapshot["c"] == "c2" }
        host.show(Table(commits: Self.commits(["a", "b", "c"]), tags: ["a2", "b2", "c2"], log: log), until: shiftedBack)
        #expect(shiftedBack())
    }

    @Test("Only the last row pages in more")
    func pagingHook() {
        let log = DrawLog()
        var appeared: [String] = []
        let onLast: (Commit) -> Void = { appeared.append($0.sha) }
        let host = Host(Table(commits: Self.commits(["a", "b"]), tags: [], log: log, onLastRowAppear: onLast),
                        until: { appeared == ["b"] })
        #expect(appeared == ["b"])
        host.show(Table(commits: Self.commits(["a", "b", "c", "d"]), tags: [], log: log, onLastRowAppear: onLast),
                  until: { appeared == ["b", "d"] })
        #expect(appeared == ["b", "d"])
    }

    @Test("A shorter log whose last row is already on screen still pages in more, once")
    func pagingAfterShrink() {
        let log = DrawLog()
        var appeared: [String] = []
        let onLast: (Commit) -> Void = { appeared.append($0.sha) }
        let host = Host(Table(commits: Self.commits(["a", "b", "c", "d"]), tags: [], log: log, onLastRowAppear: onLast),
                        until: { appeared == ["d"] })
        #expect(appeared == ["d"])
        // A reload drops the last two pages: `b`, on screen all along, is the last row now.
        host.show(Table(commits: Self.commits(["a", "b"]), tags: [], log: log, onLastRowAppear: onLast),
                  until: { appeared == ["d", "b"] })
        #expect(appeared == ["d", "b"])
    }

    @Test("A long log shown in a short viewport pages in more only once its end is scrolled to",
          arguments: [false, true])
    func longLogWaitsForTheEnd(eager: Bool) {
        let log = DrawLog()
        var appeared: [String] = []
        let onLast: (Commit) -> Void = { appeared.append($0.sha) }
        let table = { (count: Int) in
            Table(commits: Self.log(count), tags: [], log: log, onLastRowAppear: onLast, eager: eager)
        }
        let rowsDrawn = { log.snapshot["c0"] != nil && log.snapshot["c5"] != nil }
        let host = Host(table(15), height: Self.shortViewport, until: { rowsDrawn() && !appeared.isEmpty })
        #expect(rowsDrawn())
        #expect(appeared.isEmpty)
        host.scrollToEnd(until: { !appeared.isEmpty })
        #expect(appeared == ["c14"])
        // The page lands below the rows on screen: nothing more until it is scrolled to.
        host.show(table(60), until: { appeared.count > 1 })
        #expect(appeared == ["c14"])
    }

    @Test("A table wider than the window pages in more once its end is scrolled to")
    func wideTablePages() {
        let log = DrawLog()
        var appeared: [String] = []
        let onLast: (Commit) -> Void = { appeared.append($0.sha) }
        let host = Host(Table(commits: Self.log(15), tags: [], log: log, onLastRowAppear: onLast, wide: true),
                        height: Self.shortViewport, until: { log.snapshot["c0"] != nil && !appeared.isEmpty })
        #expect(appeared.isEmpty)
        host.scrollToEnd(until: { !appeared.isEmpty })
        #expect(appeared == ["c14"])
    }

    @Test("The same rows published again while the end is on screen page in more again")
    func pagingAfterRepublish() {
        let log = DrawLog()
        var appeared: [String] = []
        let onLast: (Commit) -> Void = { appeared.append($0.sha) }
        let rows = Self.commits(["a", "b", "c", "d"])
        let host = Host(Table(commits: rows, tags: [], log: log, onLastRowAppear: onLast), until: { appeared == ["d"] })
        #expect(appeared == ["d"])
        // The same log drawn again, as any re-render does: nothing to page in.
        host.show(Table(commits: rows, tags: [], log: log, onLastRowAppear: onLast), until: { appeared.count > 1 })
        #expect(appeared == ["d"])
        // A reload superseded the page load and published the same rows.
        host.show(Table(commits: rows, tags: [], log: log, onLastRowAppear: onLast, revision: 1),
                  until: { appeared == ["d", "d"] })
        #expect(appeared == ["d", "d"])
    }
}
