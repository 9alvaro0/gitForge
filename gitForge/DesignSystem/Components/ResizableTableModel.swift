import SwiftUI

/// Persisted column widths and visibility for a table, keyed by stable
/// column ID. Use one model per table.
///
/// A column listed in `autoSized` follows its content (the table decides its
/// width) until the user drags it; from then on the dragged width wins, and
/// `resetWidth` hands it back to the table.
@Observable
final class ResizableTableModel {
    private let storageKey: String
    private let manualKey: String
    private let hiddenKey: String
    private let defaults: [String: CGFloat]
    private let mins: [String: CGFloat]
    private let autoSized: Set<String>

    private(set) var widths: [String: CGFloat]
    /// Auto-sized columns the user has dragged.
    private(set) var manual: Set<String>
    private(set) var hidden: Set<String>

    init(id: String, columns: [(id: String, defaultWidth: CGFloat, minWidth: CGFloat)],
         autoSized: Set<String> = []) {
        self.storageKey = "gitForge.table.\(id).widths"
        self.manualKey = "gitForge.table.\(id).manual"
        self.hiddenKey = "gitForge.table.\(id).hidden"
        self.defaults = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0.defaultWidth) })
        self.mins = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0.minWidth) })
        self.autoSized = autoSized

        let store = UserDefaults.standard
        if let stored = store.dictionary(forKey: storageKey) as? [String: Double] {
            var resolved: [String: CGFloat] = [:]
            for (key, def) in defaults {
                if let v = stored[key] { resolved[key] = CGFloat(v) }
                else { resolved[key] = def }
            }
            self.widths = resolved
        } else {
            self.widths = defaults
        }
        let known = Set(defaults.keys)
        self.manual = Set(store.stringArray(forKey: manualKey) ?? []).intersection(autoSized)
        self.hidden = Set(store.stringArray(forKey: hiddenKey) ?? []).intersection(known)
    }

    /// Width binding for `column`. Setting only updates the in-memory widths —
    /// callers should invoke `commit()` on drag-end to persist to UserDefaults.
    /// Persisting on every keystroke caused noticeable drag lag because each
    /// `set` synchronously hit disk and triggered every observer to re-render.
    /// Setting an auto-sized column makes its width the user's.
    func binding(for column: String) -> Binding<CGFloat> {
        Binding(
            get: { self.widths[column] ?? self.defaults[column] ?? 100 },
            set: { newValue in
                let min = self.mins[column] ?? 40
                self.widths[column] = Swift.max(min, newValue)
                // Every frame of a drag lands here: only touch the set when
                // it changes, so observers aren't notified for nothing.
                if self.autoSized.contains(column), !self.manual.contains(column) {
                    self.manual.insert(column)
                }
            }
        )
    }

    func width(_ column: String) -> CGFloat {
        widths[column] ?? defaults[column] ?? 100
    }

    func minWidth(_ column: String) -> CGFloat {
        mins[column] ?? 40
    }

    /// Whether the table sizes `column` itself: it's auto-sized and the user
    /// hasn't dragged it.
    func isAutoWidth(_ column: String) -> Bool {
        autoSized.contains(column) && !manual.contains(column)
    }

    func isVisible(_ column: String) -> Bool {
        !hidden.contains(column)
    }

    func setVisible(_ column: String, _ visible: Bool) {
        guard defaults[column] != nil, visible == hidden.contains(column) else { return }
        if visible { hidden.remove(column) } else { hidden.insert(column) }
        UserDefaults.standard.set(hidden.sorted(), forKey: hiddenKey)
    }

    /// Persist the current in-memory widths. Call from `ColumnDragHandle`'s
    /// `onCommit` closure (i.e. drag-end) so the disk write happens once per
    /// gesture instead of once per frame.
    func commit() {
        persist()
    }

    /// Back to the default width, or to the table's own for an auto-sized column.
    func resetWidth(_ column: String) {
        guard let def = defaults[column] else { return }
        widths[column] = def
        manual.remove(column)
        persist()
    }

    /// Every width back to its default; auto-sized columns follow their
    /// content again. Visibility is left alone.
    func reset() {
        widths = defaults
        manual = []
        persist()
    }

    private func persist() {
        let serializable = widths.mapValues { Double($0) }
        UserDefaults.standard.set(serializable, forKey: storageKey)
        UserDefaults.standard.set(manual.sorted(), forKey: manualKey)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var columns = ResizableTableModel(
        id: "preview.demo",
        columns: [
            (id: "name", defaultWidth: 180, minWidth: 80),
            (id: "value", defaultWidth: 120, minWidth: 60),
        ]
    )
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            Text("NAME")
                .textRole(.monoSmall)
                .frame(width: columns.width("name"), alignment: .leading)
            ColumnDragHandle(
                width: columns.binding(for: "name"),
                minWidth: columns.minWidth("name"),
                maxWidth: 400,
                onCommit: { columns.commit() }
            )
            Text("VALUE")
                .textRole(.monoSmall)
                .frame(width: columns.width("value"), alignment: .leading)
            ColumnDragHandle(
                width: columns.binding(for: "value"),
                minWidth: columns.minWidth("value"),
                maxWidth: 300,
                onCommit: { columns.commit() }
            )
            Text("REST")
                .textRole(.monoSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Spacing.s8)
        .background(theme.colors.bgContent)
        Divider()
        Text("Resize columns then call columns.commit() — name=\(Int(columns.width("name"))), value=\(Int(columns.width("value")))")
            .textRole(.monoSmall)
            .padding()
        Spacer()
    }
    .frame(width: 700, height: 200)
    .background(theme.colors.bgElevated)
    .appTheme(theme)
}
