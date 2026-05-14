import SwiftUI

struct ConflictHunksColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme
    /// Index of the keyboard-focused hunk. Flechas mueven, 1/2/3 piquean.
    /// Resetea al cambiar de archivo (`.onChange` sobre `selectedConflictPath`).
    @State private var focusedHunkIndex: Int = 0

    private var hunks: [ConflictHunk] { viewModel.conflictHunks }
    private var picks: [UUID: ConflictHunk.Pick] { viewModel.conflictPicks }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxl) {
                    if let path = viewModel.selectedConflictPath {
                        pathHeader(path: path)
                    }
                    if hunks.isEmpty {
                        Text("Pick a file with unresolved conflicts on the left.")
                            .font(AppFont.sans(12))
                            .foregroundStyle(theme.palette.fg3)
                            .padding(.top, DesignTokens.Spacing.md)
                    } else {
                        keyboardHint
                    }
                    ForEach(Array(hunks.enumerated()), id: \.element.id) { index, hunk in
                        ConflictHunkCard(
                            hunk: hunk,
                            index: index,
                            pick: picks[hunk.id],
                            currentBranchName: viewModel.currentBranchName,
                            onPick: { viewModel.setConflictPick(hunkId: hunk.id, pick: $0) }
                        )
                        .overlay(focusedHunkIndex == index ? focusBorder : nil)
                        .id("hunk-\(index)")
                    }
                }
                .padding(DesignTokens.Spacing.xxxxl)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.downArrow) {
                guard let next = Self.advanceFocus(from: focusedHunkIndex, by: +1, count: hunks.count) else { return .ignored }
                focusedHunkIndex = next
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("hunk-\(next)", anchor: .center)
                }
                return .handled
            }
            .onKeyPress(.upArrow) {
                guard let prev = Self.advanceFocus(from: focusedHunkIndex, by: -1, count: hunks.count) else { return .ignored }
                focusedHunkIndex = prev
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("hunk-\(prev)", anchor: .center)
                }
                return .handled
            }
            .onKeyPress("1") { pick(.ours) }
            .onKeyPress("2") { pick(.theirs) }
            .onKeyPress("3") { pick(.both) }
            .onChange(of: viewModel.selectedConflictPath) { _, _ in
                focusedHunkIndex = 0
            }
        }
    }

    private var focusBorder: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
            .stroke(theme.palette.accent, lineWidth: DesignTokens.Stroke.regular * 2)
    }

    private var keyboardHint: some View {
        Text("↑↓ to navigate hunks · 1 pick ours · 2 pick theirs · 3 pick both")
            .font(AppFont.mono(10.5, family: theme.monoFont))
            .foregroundStyle(theme.palette.fg3)
    }

    private func pick(_ pick: ConflictHunk.Pick) -> KeyPress.Result {
        guard hunks.indices.contains(focusedHunkIndex) else { return .ignored }
        let hunk = hunks[focusedHunkIndex]
        viewModel.setConflictPick(hunkId: hunk.id, pick: pick)
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

    private func pathHeader(path: String) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            GFIcon(kind: .diff, size: 14, stroke: theme.palette.fg1)
            Text(path)
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg1)
            Text("· \(picks.count)/\(hunks.count) picked")
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
            Spacer()
            GFButton(title: "Mark resolved",
                     style: .primary,
                     size: .small,
                     disabled: hunks.isEmpty || picks.count < hunks.count) {
                Task { await viewModel.resolveSelectedFile() }
            }
        }
        .padding(.bottom, DesignTokens.Spacing.md)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: DesignTokens.Stroke.regular) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ConflictHunksColumn(viewModel: .previewWithConflicts)
        .frame(width: 760, height: 720)
        .background(theme.palette.bg2)
        .appTheme(theme)
}

