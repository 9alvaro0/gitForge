import SwiftUI

/// ↑ / ↓ move the selection through a list of rows while the list has
/// keyboard focus, scrolling the new row into view when a proxy is given.
///
/// Rows must carry `.id(_:)` with the same values as `ids` for scrolling to
/// work. Clicking a row doesn't move focus by itself (rows are plain
/// buttons), so the list's row handlers set `isFocused` to `true`.
///
/// With `onShiftMove`, Shift-↑↓ goes to it instead (by +1 / −1) — a list
/// that extends a multiple selection — and scrolls to the row it returns.
struct ListKeyboardNavigation<ID: Hashable>: ViewModifier {
    let ids: [ID]
    let selection: ID?
    var isFocused: FocusState<Bool>.Binding
    var scrollProxy: ScrollViewProxy?
    var onShiftMove: ((Int) -> ID?)?
    let onSelect: (ID) -> Void

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .focused(isFocused)
            .onKeyPress(keys: [.downArrow, .upArrow]) { press in
                let offset = press.key == .downArrow ? 1 : -1
                if press.modifiers.contains(.shift), let onShiftMove {
                    if let target = onShiftMove(offset) {
                        scrollProxy?.scrollTo(target)
                    }
                    return .handled
                }
                return move(by: offset)
            }
    }

    private func move(by offset: Int) -> KeyPress.Result {
        guard let target = Self.target(in: ids, from: selection, by: offset) else { return .ignored }
        if target != selection {
            onSelect(target)
            scrollProxy?.scrollTo(target)
        }
        return .handled
    }

    /// The id `offset` rows away from `selection`, clamped to the ends (no
    /// wrap). With no selection — or one no longer in the list — the first
    /// row. `nil` for an empty list, so the key event stays unhandled.
    static func target(in ids: [ID], from selection: ID?, by offset: Int) -> ID? {
        guard !ids.isEmpty else { return nil }
        guard let current = selection.flatMap({ ids.firstIndex(of: $0) }) else { return ids[0] }
        return ids[min(max(current + offset, 0), ids.count - 1)]
    }
}

extension View {
    /// See `ListKeyboardNavigation`.
    func listKeyboardNavigation<ID: Hashable>(
        ids: [ID],
        selection: ID?,
        isFocused: FocusState<Bool>.Binding,
        scrollProxy: ScrollViewProxy? = nil,
        onShiftMove: ((Int) -> ID?)? = nil,
        onSelect: @escaping (ID) -> Void
    ) -> some View {
        modifier(ListKeyboardNavigation(
            ids: ids,
            selection: selection,
            isFocused: isFocused,
            scrollProxy: scrollProxy,
            onShiftMove: onShiftMove,
            onSelect: onSelect
        ))
    }
}
