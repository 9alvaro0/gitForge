import SwiftUI

/// Persisted column widths for a table, keyed by stable column ID. Values
/// auto-save to `UserDefaults` whenever they change. Use one model per table.
@Observable
final class ResizableTableModel {
    private let storageKey: String
    private let defaults: [String: CGFloat]
    private let mins: [String: CGFloat]

    private(set) var widths: [String: CGFloat]

    init(id: String, columns: [(id: String, defaultWidth: CGFloat, minWidth: CGFloat)]) {
        self.storageKey = "gitForge.table.\(id).widths"
        self.defaults = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0.defaultWidth) })
        self.mins = Dictionary(uniqueKeysWithValues: columns.map { ($0.id, $0.minWidth) })

        if let stored = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double] {
            var resolved: [String: CGFloat] = [:]
            for (key, def) in defaults {
                if let v = stored[key] { resolved[key] = CGFloat(v) }
                else { resolved[key] = def }
            }
            self.widths = resolved
        } else {
            self.widths = defaults
        }
    }

    /// Width binding for `column`. Setting only updates the in-memory widths —
    /// callers should invoke `commit()` on drag-end to persist to UserDefaults.
    /// Persisting on every keystroke caused noticeable drag lag because each
    /// `set` synchronously hit disk and triggered every observer to re-render.
    func binding(for column: String) -> Binding<CGFloat> {
        Binding(
            get: { self.widths[column] ?? self.defaults[column] ?? 100 },
            set: { newValue in
                let min = self.mins[column] ?? 40
                self.widths[column] = Swift.max(min, newValue)
            }
        )
    }

    func width(_ column: String) -> CGFloat {
        widths[column] ?? defaults[column] ?? 100
    }

    func minWidth(_ column: String) -> CGFloat {
        mins[column] ?? 40
    }

    /// Persist the current in-memory widths. Call from `ColumnDragHandle`'s
    /// `onCommit` closure (i.e. drag-end) so the disk write happens once per
    /// gesture instead of once per frame.
    func commit() {
        persist()
    }

    func reset() {
        widths = defaults
        persist()
    }

    private func persist() {
        let serializable = widths.mapValues { Double($0) }
        UserDefaults.standard.set(serializable, forKey: storageKey)
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
    VStack(spacing: DesignTokens.Spacing.none) {
        HStack(spacing: DesignTokens.Spacing.none) {
            Text("NAME")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(width: columns.width("name"), alignment: .leading)
            ColumnDragHandle(
                width: columns.binding(for: "name"),
                minWidth: columns.minWidth("name"),
                maxWidth: 400,
                onCommit: { columns.commit() }
            )
            Text("VALUE")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(width: columns.width("value"), alignment: .leading)
            ColumnDragHandle(
                width: columns.binding(for: "value"),
                minWidth: columns.minWidth("value"),
                maxWidth: 300,
                onCommit: { columns.commit() }
            )
            Text("REST")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DesignTokens.Spacing.md)
        .background(theme.palette.bg2)
        Divider()
        Text("Resize columns then call columns.commit() — name=\(Int(columns.width("name"))), value=\(Int(columns.width("value")))")
            .font(AppFont.mono(11, family: theme.monoFont))
            .padding()
        Spacer()
    }
    .frame(width: 700, height: 200)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
