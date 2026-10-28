import AppKit
import Foundation
import Testing
@testable import gitForge

@Suite("Changes — ⌘ / Shift ticking")
@MainActor
struct StagingTickingTests {

    private nonisolated static func u(_ path: String) -> WorkingCopyRowID { WorkingCopyRowID(side: .unstaged, path: path) }
    private nonisolated static func s(_ path: String) -> WorkingCopyRowID { WorkingCopyRowID(side: .staged, path: path) }

    private let unstaged = ["a", "b", "c", "d", "e"].map(Self.u)
    private let staged = ["x", "y"].map(Self.s)

    @Test("⌘-click flips the row and anchors there")
    func toggle() {
        var t = StagingTicking()
        var ticked: Set<String> = []
        t.toggle(Self.u("b"), ticked: &ticked)
        #expect(ticked == ["b"])
        #expect(t.anchor == Self.u("b"))
        t.toggle(Self.u("b"), ticked: &ticked)
        #expect(ticked.isEmpty)
    }

    @Test("Shift ticks the whole run from the anchor, in either direction")
    func extendRun() {
        var t = StagingTicking()
        var ticked: Set<String> = []
        t.setAnchor(Self.u("b"))
        t.extend(to: Self.u("d"), rows: unstaged, fallback: nil, ticked: &ticked)
        #expect(ticked == ["b", "c", "d"])
        #expect(t.head == Self.u("d"))

        var up = StagingTicking()
        var tickedUp: Set<String> = []
        up.setAnchor(Self.u("d"))
        up.extend(to: Self.u("b"), rows: unstaged, fallback: nil, ticked: &tickedUp)
        #expect(tickedUp == ["b", "c", "d"])
    }

    @Test("Pulling the run back shrinks it, keeping files ticked before the run")
    func shrinkKeepsEarlierTicks() {
        var t = StagingTicking()
        var ticked: Set<String> = ["c", "elsewhere"]
        t.setAnchor(Self.u("a"))
        t.extend(to: Self.u("e"), rows: unstaged, fallback: nil, ticked: &ticked)
        #expect(ticked == ["a", "b", "c", "d", "e", "elsewhere"])
        t.extend(to: Self.u("b"), rows: unstaged, fallback: nil, ticked: &ticked)
        #expect(ticked == ["a", "b", "c", "elsewhere"])
        t.extend(to: Self.u("a"), rows: unstaged, fallback: nil, ticked: &ticked)
        #expect(ticked == ["a", "c", "elsewhere"])
    }

    @Test("⌘-click after a run starts a new one; the old run stays ticked")
    func toggleEndsRun() {
        var t = StagingTicking()
        var ticked: Set<String> = []
        t.setAnchor(Self.u("a"))
        t.extend(to: Self.u("b"), rows: unstaged, fallback: nil, ticked: &ticked)
        t.toggle(Self.u("d"), ticked: &ticked)
        t.extend(to: Self.u("e"), rows: unstaged, fallback: nil, ticked: &ticked)
        #expect(ticked == ["a", "b", "d", "e"])
    }

    @Test("After the ticks change elsewhere, a new extend doesn't untick the old run")
    func forgetRun() {
        var t = StagingTicking()
        var ticked: Set<String> = []
        t.setAnchor(Self.u("a"))
        t.extend(to: Self.u("c"), rows: unstaged, fallback: nil, ticked: &ticked)
        t.forgetRun()
        t.extend(to: Self.u("b"), rows: unstaged, fallback: nil, ticked: &ticked)
        #expect(ticked == ["a", "b", "c"])
    }

    @Test("Without an anchor in the section the run starts at the open row, else at the target")
    func fallbackStart() {
        var t = StagingTicking()
        var ticked: Set<String> = []
        t.setAnchor(Self.s("x"))   // other section: ignored
        t.extend(to: Self.u("c"), rows: unstaged, fallback: Self.u("a"), ticked: &ticked)
        #expect(ticked == ["a", "b", "c"])
        #expect(t.anchor == Self.u("a"))

        var alone = StagingTicking()
        var tickedAlone: Set<String> = []
        alone.extend(to: Self.u("c"), rows: unstaged, fallback: Self.s("y"), ticked: &tickedAlone)
        #expect(tickedAlone == ["c"])
        #expect(alone.anchor == Self.u("c"))
    }

    @Test("A target missing from the rows does nothing")
    func missingTarget() {
        var t = StagingTicking()
        var ticked: Set<String> = []
        t.extend(to: Self.u("zzz"), rows: unstaged, fallback: Self.u("a"), ticked: &ticked)
        #expect(ticked.isEmpty)
        #expect(t.anchor == nil)
    }

    @Test("Shift-↑↓ steps from the run's far end, else the open row, and stops at the section's edge")
    func stepTarget() {
        var t = StagingTicking()
        var ticked: Set<String> = []
        let sections = [unstaged, staged]
        #expect(t.stepTarget(by: 1, current: Self.u("b"), sections: sections) == Self.u("c"))
        #expect(t.stepTarget(by: 1, current: nil, sections: sections) == nil)

        t.setAnchor(Self.u("b"))
        t.extend(to: Self.u("d"), rows: unstaged, fallback: nil, ticked: &ticked)
        #expect(t.stepTarget(by: 1, current: Self.u("b"), sections: sections) == Self.u("e"))
        #expect(t.stepTarget(by: -1, current: Self.u("b"), sections: sections) == Self.u("c"))

        // The last Unstaged row doesn't step into Staged, nor the first Staged row back up.
        #expect(StagingTicking().stepTarget(by: 1, current: Self.u("e"), sections: sections) == nil)
        #expect(StagingTicking().stepTarget(by: -1, current: Self.s("x"), sections: sections) == nil)
    }

    @Test("Click kind follows the modifiers: ⌘ wins over Shift, others just open")
    func clickKind() {
        #expect(StagingRowClick(modifiers: []) == .open)
        #expect(StagingRowClick(modifiers: .command) == .toggleTick)
        #expect(StagingRowClick(modifiers: .shift) == .extendTicks)
        #expect(StagingRowClick(modifiers: [.command, .shift]) == .toggleTick)
        #expect(StagingRowClick(modifiers: .option) == .open)
    }

    @Test("⌘A ticks the section and ⌘⌫ discards; other keys and modifiers pass through")
    func keyCommands() {
        #expect(StagingKeyCommand(characters: "a", modifiers: .command) == .tickSection)
        #expect(StagingKeyCommand(characters: "\u{7F}", modifiers: .command) == .discard)
        #expect(StagingKeyCommand(characters: "a", modifiers: [.command, .shift]) == nil)
        #expect(StagingKeyCommand(characters: "\u{7F}", modifiers: [.command, .option]) == nil)
        #expect(StagingKeyCommand(characters: "r", modifiers: .command) == nil)
    }

    // MARK: Store

    private static func file(_ path: String) -> WorkingCopyFile {
        WorkingCopyFile(path: path, stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil)
    }

    private static func makeViewModel() -> RepositoryViewModel {
        RepositoryViewModel(repository: Repository(url: URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")))
    }

    @Test("Shift-↓ from the open row ticks both rows and opens the next one")
    func storeStep() {
        let vm = Self.makeViewModel()
        let store = vm.workingCopy
        store.status = WorkingCopyStatus(files: ["a", "b", "c"].map(Self.file))
        let rows = ["a", "b", "c"].map(Self.u)
        store.select(rows[0], in: store.status.files)
        store.noteOpened(rows[0])

        #expect(store.extendTicks(by: 1, sections: [rows, []]) == rows[1])
        #expect(store.selectedFilePaths == ["a", "b"])
        #expect(store.selectedRowID == rows[1])

        #expect(store.extendTicks(by: 1, sections: [rows, []]) == rows[2])
        #expect(store.extendTicks(by: 1, sections: [rows, []]) == nil)
        #expect(store.extendTicks(by: -1, sections: [rows, []]) == rows[1])
        #expect(store.selectedFilePaths == ["a", "b"])
    }

    @Test("Shift-click with no anchor starts from the open row")
    func storeShiftClick() {
        let vm = Self.makeViewModel()
        let store = vm.workingCopy
        store.status = WorkingCopyStatus(files: ["a", "b", "c"].map(Self.file))
        let rows = ["a", "b", "c"].map(Self.u)
        store.select(rows[2], in: store.status.files)
        store.extendTicks(to: rows[0], rows: rows)
        #expect(store.selectedFilePaths == ["a", "b", "c"])
        #expect(store.selectedRowID == rows[2], "Shift-click doesn't move the open diff")
    }

    @Test("Esc clears every tick, and reports when there was nothing to clear")
    func storeClear() {
        let store = Self.makeViewModel().workingCopy
        #expect(store.clearTicks() == false)
        store.toggleTick(Self.u("a"))
        store.toggleTick(Self.s("x"))
        #expect(store.clearTicks())
        #expect(store.selectedFilePaths.isEmpty)
    }
}
