import SwiftUI

/// 8pt-wide hit area with a 1pt visible divider centered inside. Drag with
/// the standard column-resize cursor; the bound `width` is clamped between
/// `minWidth` and `maxWidth` while dragging.
///
/// Each handle controls the column to its LEFT — neighbours stay put, like
/// every native table on macOS.
struct ColumnDragHandle: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 40
    var maxWidth: CGFloat = 1200

    @State private var startWidth: CGFloat?
    @Environment(\.appTheme) private var theme

    var body: some View {
        // Color.clear has 0 intrinsic size — fills the row's height set by
        // its sibling Text views. Setting only `.frame(width:)` lets the
        // height stay flexible, so the handle never bloats the row.
        Color.clear
            .frame(width: 8)
            .overlay(Rectangle().fill(theme.palette.line).frame(width: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        let new = base + value.translation.width
                        width = min(max(minWidth, new), maxWidth)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .pointerStyle(.columnResize)
    }
}

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

    /// Width binding for `column`. Setting writes through to UserDefaults so
    /// drags persist between launches without manual save calls.
    func binding(for column: String) -> Binding<CGFloat> {
        Binding(
            get: { self.widths[column] ?? self.defaults[column] ?? 100 },
            set: { newValue in
                let min = self.mins[column] ?? 40
                self.widths[column] = Swift.max(min, newValue)
                self.persist()
            }
        )
    }

    func width(_ column: String) -> CGFloat {
        widths[column] ?? defaults[column] ?? 100
    }

    func minWidth(_ column: String) -> CGFloat {
        mins[column] ?? 40
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
    @Previewable @State var w1: CGFloat = 200
    @Previewable @State var w2: CGFloat = 120
    VStack(spacing: 0) {
        HStack(spacing: 0) {
            Text("ALPHA")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(width: w1, alignment: .leading)
            ColumnDragHandle(width: $w1, minWidth: 80, maxWidth: 400)
            Text("BETA")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(width: w2, alignment: .leading)
            ColumnDragHandle(width: $w2, minWidth: 60, maxWidth: 300)
            Text("GAMMA")
                .font(AppFont.mono(10.5, family: theme.monoFont))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 8)
        .background(theme.palette.bg2)
        Divider()
        Text("Drag the dividers — w1=\(Int(w1)), w2=\(Int(w2))")
            .font(AppFont.mono(11, family: theme.monoFont))
            .padding()
        Spacer()
    }
    .frame(width: 700, height: 200)
    .background(theme.palette.bg1)
    .appTheme(theme)
}
