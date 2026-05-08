import SwiftUI

/// 8pt-wide hit area with a 1pt visible divider centered inside. Drag with
/// the standard column-resize cursor; the bound `width` is clamped between
/// `minWidth` and `maxWidth` while dragging.
///
/// By default each handle controls the column to its LEFT — neighbours stay
/// put, like every native table on macOS. Set `inverted: true` when the
/// handle sits at the LEADING edge of the column it resizes (e.g. the right
/// detail panel in History): drag right then shrinks it instead of growing it.
/// `onCommit` fires on drag-end so callers can defer expensive work
/// (UserDefaults writes) until the user lets go, instead of paying that cost
/// on every frame of the drag.
struct ColumnDragHandle: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 40
    var maxWidth: CGFloat = 1200
    var inverted: Bool = false
    var dividerColor: Color?
    var onCommit: () -> Void = {}

    @State private var startWidth: CGFloat?
    @Environment(\.appTheme) private var theme

    var body: some View {
        // Color.clear has 0 intrinsic size — fills the row's height set by
        // its sibling Text views. Setting only `.frame(width:)` lets the
        // height stay flexible, so the handle never bloats the row.
        Color.clear
            .frame(width: 8)
            .overlay(
                Rectangle()
                    .fill(dividerColor ?? theme.palette.line)
                    .frame(width: 1)
                    .allowsHitTesting(false)
            )
            .contentShape(.rect)
            .gesture(
                // `.global` keeps translation stable when the handle's frame
                // moves during the drag (which it does, because the column it
                // controls is growing). `.local` produced a feedback loop
                // where the cursor "caught up" with the handle and the gesture
                // appeared reversed.
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? width
                        if startWidth == nil { startWidth = width }
                        let delta = inverted ? -value.translation.width : value.translation.width
                        let new = base + delta
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            width = min(max(minWidth, new), maxWidth)
                        }
                    }
                    .onEnded { _ in
                        startWidth = nil
                        onCommit()
                    }
            )
            .pointerStyle(.columnResize)
    }
}

/// Horizontal divider you drag vertically to resize the height of the pane
/// BELOW the handle (e.g. the diff pane below the History table). Drag up =
/// pane grows, drag down = pane shrinks.
struct RowDragHandle: View {
    @Binding var height: CGFloat
    var minHeight: CGFloat = 60
    var maxHeight: CGFloat = 800
    var onCommit: () -> Void = {}

    @State private var startHeight: CGFloat?
    @Environment(\.appTheme) private var theme

    var body: some View {
        Color.clear
            .frame(height: 8)
            .overlay(
                Rectangle()
                    .fill(theme.palette.lineStrong)
                    .frame(height: 1)
                    .allowsHitTesting(false)
            )
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startHeight ?? height
                        if startHeight == nil { startHeight = height }
                        // Handle is at the TOP of the resizable pane: drag up
                        // (negative dy) = pane gets taller.
                        let new = base - value.translation.height
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            height = min(max(minHeight, new), maxHeight)
                        }
                    }
                    .onEnded { _ in
                        startHeight = nil
                        onCommit()
                    }
            )
            .pointerStyle(.rowResize)
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
    @Previewable @State var w1: CGFloat = 200
    @Previewable @State var w2: CGFloat = 120
    VStack(spacing: DesignTokens.Spacing.none) {
        HStack(spacing: DesignTokens.Spacing.none) {
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
        .padding(.vertical, DesignTokens.Spacing.md)
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
