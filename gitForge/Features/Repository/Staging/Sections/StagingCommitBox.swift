import SwiftUI

struct StagingCommitBox: View {
    @Bindable var viewModel: RepositoryViewModel
    let stagedCount: Int
    @Binding var commitMessage: String
    @Binding var commitDescription: String

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            TextField("Commit message", text: $commitMessage)
                .textFieldStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
                .font(AppFont.sans(12.5))

            TextField("Description (optional)", text: $commitDescription, axis: .vertical)
                .lineLimit(3...3)
                .textFieldStyle(.plain)
                .padding(.horizontal, DesignTokens.Spacing.lg).padding(.vertical, DesignTokens.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg3))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.lineStrong, lineWidth: DesignTokens.Stroke.regular))
                .font(AppFont.mono(12, family: theme.monoFont))

            HStack {
                MonoText("on \(viewModel.currentBranchName ?? "HEAD") · \(stagedCount) files", dim: true)
                Spacer()
                GFButton(title: "Commit & push") { Task { await commit(push: true) } }
                GFButton(title: "Commit", style: .primary,
                         disabled: commitMessage.isEmpty || stagedCount == 0) {
                    Task { await commit(push: false) }
                }
            }

            if let error = viewModel.commitError {
                Text(error)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.del)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .background(theme.palette.bg2)
        .overlay(alignment: .top) { Rectangle().fill(theme.palette.lineStrong).frame(height: DesignTokens.Stroke.regular) }
    }

    private func commit(push: Bool) async {
        viewModel.commitSubject = commitMessage
        viewModel.commitBody = commitDescription
        let ok = await viewModel.commit()
        if ok, push { await viewModel.push() }
        if ok { commitMessage = ""; commitDescription = "" }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    @Previewable @State var message = ""
    @Previewable @State var description = ""
    StagingCommitBox(
        viewModel: .preview,
        stagedCount: 3,
        commitMessage: $message,
        commitDescription: $description
    )
    .frame(width: 380)
    .appTheme(theme)
}
