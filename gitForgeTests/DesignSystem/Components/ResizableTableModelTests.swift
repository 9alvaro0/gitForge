import Foundation
import SwiftUI
import Testing
@testable import gitForge

@Suite("ResizableTableModel")
@MainActor
struct ResizableTableModelTests {

    /// A table id of its own per test, its keys removed afterwards.
    private func withModel(autoSized: Set<String> = ["graph"],
                           _ body: (ResizableTableModel, () -> ResizableTableModel) -> Void) {
        let id = "tests.\(UUID().uuidString)"
        defer {
            for suffix in ["widths", "manual", "hidden"] {
                UserDefaults.standard.removeObject(forKey: "gitForge.table.\(id).\(suffix)")
            }
        }
        let make = {
            ResizableTableModel(id: id,
                                columns: [(id: "graph", defaultWidth: 80, minWidth: 60),
                                          (id: "author", defaultWidth: 112, minWidth: 80)],
                                autoSized: autoSized)
        }
        body(make(), make)
    }

    @Test("An auto-sized column follows the table until dragged")
    func autoUntilDragged() {
        withModel { model, _ in
            #expect(model.isAutoWidth("graph"))
            #expect(!model.isAutoWidth("author"))
            model.binding(for: "graph").wrappedValue = 150
            #expect(!model.isAutoWidth("graph"))
            #expect(model.width("graph") == 150)
        }
    }

    @Test("Dragging clamps to the column minimum")
    func clampsToMinimum() {
        withModel { model, _ in
            model.binding(for: "author").wrappedValue = 10
            #expect(model.width("author") == 80)
        }
    }

    @Test("Resetting a column hands an auto-sized one back to the table")
    func resetWidth() {
        withModel { model, _ in
            model.binding(for: "graph").wrappedValue = 150
            model.binding(for: "author").wrappedValue = 200
            model.resetWidth("graph")
            #expect(model.isAutoWidth("graph"))
            #expect(model.width("graph") == 80)
            #expect(model.width("author") == 200)
        }
    }

    @Test("Resetting all widths clears every drag")
    func resetAll() {
        withModel { model, _ in
            model.binding(for: "graph").wrappedValue = 150
            model.binding(for: "author").wrappedValue = 200
            model.reset()
            #expect(model.isAutoWidth("graph"))
            #expect(model.width("author") == 112)
        }
    }

    @Test("Widths and drags persist once committed")
    func persistsCommitted() {
        withModel { model, make in
            model.binding(for: "graph").wrappedValue = 150
            model.commit()
            let reloaded = make()
            #expect(reloaded.width("graph") == 150)
            #expect(!reloaded.isAutoWidth("graph"))
        }
    }

    @Test("Hidden columns persist; unknown columns are ignored")
    func visibility() {
        withModel { model, make in
            #expect(model.isVisible("author"))
            model.setVisible("author", false)
            model.setVisible("nope", false)
            #expect(!model.isVisible("author"))
            #expect(model.hidden == ["author"])
            #expect(!make().isVisible("author"))
            model.setVisible("author", true)
            #expect(make().isVisible("author"))
        }
    }

    @Test("Resetting widths leaves visibility alone")
    func resetKeepsVisibility() {
        withModel { model, _ in
            model.setVisible("author", false)
            model.reset()
            #expect(!model.isVisible("author"))
        }
    }

    @Test("History's hidden ids map onto its layout columns")
    func historyColumns() {
        let id = "tests.history.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: "gitForge.table.\(id).hidden") }
        let model = ResizableTableModel.historyColumns(id: id)
        model.setVisible("when", false)
        model.setVisible("sha", false)
        #expect(model.hiddenHistoryColumns == [.date, .commit])
        #expect(model.isAutoWidth("graph"))
    }
}
