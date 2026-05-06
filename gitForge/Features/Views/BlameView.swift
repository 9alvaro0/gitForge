import SwiftUI

/// `.gf-view-blame` — file blame view backed by `git blame --porcelain`.
struct BlameView: View {
    @Bindable var viewModel: RepositoryViewModel
    @Environment(\.appTheme) private var theme

    @State private var pathInput: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Blame") {
                MonoText(viewModel.selectedBlamePath ?? "—", dim: true)
            } right: {
                HStack(spacing: 6) {
                    GFTextField(placeholder: "path/to/file", text: $pathInput).frame(width: 260)
                    GFButton(title: "Run blame", style: .primary, disabled: pathInput.isEmpty) {
                        Task { await viewModel.loadBlame(path: pathInput) }
                    }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingBlame {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.blameError {
            EmptyState(icon: .warn, title: "Blame failed", subtitle: error) { EmptyView() }
        } else if viewModel.blameGroups.isEmpty {
            EmptyState(icon: .blame,
                       title: viewModel.selectedBlamePath == nil ? "Pick a file to blame" : "Empty blame output",
                       subtitle: viewModel.selectedBlamePath == nil ? "Type a path and press Run blame." : nil) {
                EmptyView()
            }
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.blameGroups) { group in
                        BlameGroupView(group: group)
                    }
                }
            }
        }
    }
}

private struct BlameGroupView: View {
    let group: BlameGroup
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Avatar(name: group.author, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.author)
                            .font(AppFont.sans(12, weight: .medium))
                            .foregroundStyle(theme.palette.fg1)
                        Text("\(group.sha) · \(group.when)")
                            .font(AppFont.mono(11, family: theme.monoFont))
                            .foregroundStyle(theme.palette.fg3)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 200, alignment: .leading)
            .background(theme.palette.bg1)
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.palette.line).frame(width: 1)
            }

            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: group.laneColorHex).opacity(0.7)).frame(width: 2)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.lines) { line in
                        HStack(spacing: 0) {
                            Text("\(line.number)")
                                .font(AppFont.mono(11, family: theme.monoFont))
                                .foregroundStyle(theme.palette.fg4)
                                .frame(width: 36, alignment: .trailing)
                                .padding(.trailing, 12)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                                .foregroundStyle(theme.palette.fg1)
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.line).frame(height: 1)
        }
    }
}

#Preview("Empty") {
    @Previewable @State var theme = AppTheme()
    BlameView(viewModel: RepositoryViewModel.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
