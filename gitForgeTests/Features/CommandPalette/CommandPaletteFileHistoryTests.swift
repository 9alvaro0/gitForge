import Foundation
import Testing
@testable import gitForge

/// ⌘K's way into File history: every tracked file is a Files row, found
/// by searching, that opens the sheet.
@Suite("Command palette file history", .serialized)
@MainActor
struct CommandPaletteFileHistoryTests {

    private static func build(trackedFiles: [String], workingFiles: [WorkingCopyFile] = []) -> [CommandPaletteItem] {
        CommandPaletteBuilder.build(repositories: [], branches: [], commits: [], workingFiles: workingFiles,
                                    trackedFiles: trackedFiles)
    }

    @Test("Each tracked file is a Files row that opens its history, found only by searching")
    func rows() throws {
        let items = Self.build(trackedFiles: ["src/App.swift", "README.md"]).filter { $0.kind == .file }

        #expect(items.map(\.label) == ["src/App.swift", "README.md"])
        #expect(items.map(\.action) == [.showFileHistory(path: "src/App.swift"), .showFileHistory(path: "README.md")])
        #expect(items.allSatisfy { $0.searchOnly && $0.hint == "File history" })
    }

    @Test("A changed file keeps its row for Changes, and its history row follows")
    func changedFileHasBoth() {
        let changed = WorkingCopyFile(path: "a.txt", stagedStatus: .unmodified, unstagedStatus: .modified, originalPath: nil)
        let items = Self.build(trackedFiles: ["a.txt"], workingFiles: [changed]).filter { $0.kind == .file }

        #expect(items.map(\.action) == [.revealFile(path: "a.txt"), .showFileHistory(path: "a.txt")])
    }

    @Test("Searching the Files scope finds a tracked file; browsing it doesn't list them")
    func searching() {
        let items = Self.build(trackedFiles: ["src/Features/Blame/BlameView.swift", "src/App.swift"])

        let found = CommandPaletteSections.build(items: items, query: "blameview", scope: .only(.file))
        #expect(found.flatMap(\.rows).map(\.item.action) == [.showFileHistory(path: "src/Features/Blame/BlameView.swift")])

        let browsing = CommandPaletteSections.build(items: items, query: "", scope: .only(.file))
        #expect(browsing.flatMap(\.rows).isEmpty)
    }

    @Test("At most trackedFileLimit files are offered")
    func limit() {
        let paths = (0...CommandPaletteBuilder.trackedFileLimit).map { "f\($0).txt" }
        let items = Self.build(trackedFiles: paths).filter { $0.kind == .file }

        #expect(items.count == CommandPaletteBuilder.trackedFileLimit)
    }

    @Test("Opening it presents a sheet, so ⌘↵ still closes the palette")
    func presentsUI() {
        #expect(PaletteAction.showFileHistory(path: "a").presentsUI)
        #expect(!PaletteAction.keepOpen(.showFileHistory(path: "a"), commandHeld: true))
    }

    @Test("The router opens the sheet on the file with a repository, and does nothing without one")
    func route() {
        let app = AppState.isolated()
        PaletteActionRouter(appState: app).route(.showFileHistory(path: "a.txt"))
        #expect(app.ui.fileInspectorRequest == nil)

        let url = URL(fileURLWithPath: "/var/empty/gitForge-tests-\(UUID().uuidString)")
        app.catalog.activeViewModel = RepositoryViewModel(repository: Repository(url: url))
        PaletteActionRouter(appState: app).route(.showFileHistory(path: "a.txt"))
        #expect(app.ui.fileInspectorRequest?.path == "a.txt")
        #expect(app.ui.fileInspectorRequest?.revision == nil)
    }
}
