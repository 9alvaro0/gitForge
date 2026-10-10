import SwiftUI

/// The selected file's hunks, open ones side by side and picked ones folded.
/// Keyboard: ↑↓ move between hunks, 1 / 2 / 3 / 4 pick ours / theirs /
/// both / both with theirs first.
struct ConflictHunksColumn: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme
    /// Index of the keyboard-focused hunk. Reset when the selected file
    /// changes (`.onChange` on `conflicts.selectedPath`).
    @State private var focusedHunkIndex: Int = 0

    private var hunks: [ConflictHunk] { viewModel.conflicts.hunks }
    private var picks: [UUID: ConflictHunk.Pick] { viewModel.conflicts.picks }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(hunks.enumerated()), id: \.element.id) { index, hunk in
                        ConflictHunkView(
                            hunk: hunk,
                            index: index,
                            pick: picks[hunk.id],
                            isFocused: focusedHunkIndex == index && hunks.count > 1,
                            onPick: { viewModel.conflicts.setPick(hunkId: hunk.id, pick: $0) },
                            onClear: { viewModel.conflicts.clearPick(hunkId: hunk.id) }
                        )
                        .id("hunk-\(index)")
                    }
                    if !hunks.isEmpty {
                        keyboardHint
                    }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) {
                guard let next = Self.advanceFocus(from: focusedHunkIndex, by: +1, count: hunks.count) else { return .ignored }
                focusedHunkIndex = next
                withAnimation(DesignTokens.Motion.standard) {
                    proxy.scrollTo("hunk-\(next)", anchor: .center)
                }
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard let prev = Self.advanceFocus(from: focusedHunkIndex, by: -1, count: hunks.count) else { return .ignored }
                focusedHunkIndex = prev
                withAnimation(DesignTokens.Motion.standard) {
                    proxy.scrollTo("hunk-\(prev)", anchor: .center)
                }
                return .handled
            }
            .onKeyPress("1") { pick(.ours) }
            .onKeyPress("2") { pick(.theirs) }
            .onKeyPress("3") { pick(.both) }
            .onKeyPress("4") { pick(.bothTheirsFirst) }
            .onChange(of: viewModel.conflicts.selectedPath) { _, _ in
                focusedHunkIndex = 0
            }
        }
    }

    private var keyboardHint: some View {
        HStack(spacing: Spacing.s6) {
            Kbd(text: "↑↓")
            Text("move between hunks")
            Kbd(text: "1")
            Text("ours")
            Kbd(text: "2")
            Text("theirs")
            Kbd(text: "3")
            Text("both")
            Kbd(text: "4")
            Text("both, theirs first")
            Spacer(minLength: 0)
        }
        .textRole(.caption)
        .foregroundStyle(theme.colors.textTertiary)
        .padding(Spacing.s12)
        .accessibilityElement(children: .combine)
    }

    private func pick(_ pick: ConflictHunk.Pick) -> KeyPress.Result {
        guard hunks.indices.contains(focusedHunkIndex) else { return .ignored }
        let hunk = hunks[focusedHunkIndex]
        viewModel.conflicts.setPick(hunkId: hunk.id, pick: pick)
        return .handled
    }

    /// Pure navigation helper: returns the next valid focus index, or nil
    /// when the list is empty (the caller should leave the key event
    /// `.ignored` so the system can do something else with it). Exposed
    /// `static` + `internal` for unit testing.
    static func advanceFocus(from current: Int, by delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let target = current + delta
        return min(max(target, 0), count - 1)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ConflictHunksColumn(viewModel: .previewWithConflicts)
        .frame(width: 760, height: 520)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
