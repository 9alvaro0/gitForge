import Foundation
import Testing
@testable import gitForge

@Suite("UndoStore")
@MainActor
struct UndoStoreTests {
    private let drop = UndoOperation.dropStash(sha: String(repeating: "a", count: 40), message: "On main: wip")

    @Test("Recording replaces what was on offer; recording nil offers nothing")
    func recordReplaces() {
        let store = UndoStore()
        let first = store.record(drop)
        let second = store.record(.discard(.init(snapshot: "t", paths: ["a"], fingerprint: "")))
        #expect(first?.id != second?.id)
        #expect(store.pending == second)
        store.record(nil)
        #expect(store.pending == nil)
    }

    @Test("Taking by id only takes that entry, and only once")
    func takeById() throws {
        let store = UndoStore()
        let entry = try #require(store.record(drop))
        #expect(store.take(id: UUID()) == nil)
        #expect(store.pending == entry)
        #expect(store.take(id: entry.id) == entry)
        #expect(store.take() == nil)
    }

    @Test("Invalidate withdraws the entry; restore puts it back")
    func invalidateAndRestore() throws {
        let store = UndoStore()
        let entry = try #require(store.record(drop))
        store.invalidate()
        #expect(store.pending == nil)
        store.restore(entry)
        #expect(store.pending == entry)
    }
}

@Suite("UndoMenuRouting")
struct UndoMenuRoutingTests {
    @Test("⌘Z undoes typing while text is edited, the repository's operation otherwise")
    func routes() {
        #expect(UndoMenuRouting.route(editingText: true, repositoryUndoOffered: true) == .responderChain)
        #expect(UndoMenuRouting.route(editingText: false, repositoryUndoOffered: true) == .repository)
        #expect(UndoMenuRouting.route(editingText: false, repositoryUndoOffered: false) == .responderChain)
    }
}

@Suite("OperationSuccess — discard")
struct OperationSuccessDiscardTests {
    @Test("Says what was discarded and where untracked files went")
    func discardMessages() {
        let id = UUID()
        let both = OperationSuccess.discard(files: 2, removal: .init(trashed: 1, deleted: 0), undoID: id)
        #expect(both.message == "Discarded changes in 2 files. Moved 1 untracked file to the Trash")
        #expect(both.undoID == id)
        #expect(OperationSuccess.discard(files: 1, removal: .init(), undoID: nil).message == "Discarded changes in 1 file")
        #expect(OperationSuccess.discard(files: 0, removal: .init(trashed: 0, deleted: 3), undoID: nil).message
            == "Deleted 3 untracked files (their disk has no Trash)")
        #expect(OperationSuccess.discardHunk(lines: true, undoID: nil).message == "Discarded the selected lines")
    }
}
