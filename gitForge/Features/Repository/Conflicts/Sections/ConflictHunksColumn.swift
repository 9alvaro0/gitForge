import SwiftUI

struct ConflictHunksColumn: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme

    private var hunks: [ConflictHunk] { viewModel.conflictHunks }
    private var picks: [UUID: ConflictHunk.Pick] { viewModel.conflictPicks }

    var body: some View {
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
                }
                ForEach(Array(hunks.enumerated()), id: \.element.id) { index, hunk in
                    ConflictHunkCard(
                        hunk: hunk,
                        index: index,
                        pick: picks[hunk.id],
                        currentBranchName: viewModel.currentBranchName,
                        onPick: { viewModel.setConflictPick(hunkId: hunk.id, pick: $0) }
                    )
                }
            }
            .padding(DesignTokens.Spacing.xxxxl)
        }
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

