import SwiftUI
import AppKit

/// Right-side commit detail in the History view.
struct CommitDetailColumn: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel
    /// Optional handler for the close icon at the panel top. When `nil` the
    /// button is hidden — used by History to collapse the panel.
    var onClose: (() -> Void)? = nil

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    private var detail: CommitDetail? { viewModel.detailCache[commit.sha] }

    /// Inspector header (redesign spec §6.2, History artboard): title,
    /// author and date, SHA, parents, message; then files and actions.
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s16) {
            VStack(alignment: .leading, spacing: Spacing.s8) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                    Text(commit.subject)
                        .textRole(.title)
                        .foregroundStyle(theme.colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let onClose {
                        IconButton(.x, accessibilityLabel: "Hide commit detail", action: onClose)
                            .help("Hide commit detail")
                    }
                }
                authorLine
                parentLine
                if let detail, !detail.bodyText.isEmpty {
                    Text(CommitMessage.reflow(detail.bodyText))
                        .textRole(.callout)
                        .foregroundStyle(theme.colors.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Spacing.s4)
                }
            }
            CommitFilesSection(commit: commit, viewModel: viewModel)
            CommitActionsSection(commit: commit, viewModel: viewModel)
        }
        .task(id: commit.sha) {
            _ = await viewModel.detail(for: commit)
        }
    }

    private var authorLine: some View {
        HStack(spacing: Spacing.s8) {
            Avatar(name: commit.authorName, size: 22, colorSeed: commit.authorEmail)
            Text(commit.authorName)
                .textRole(.callout, weight: .medium)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(1)
                .help(commit.authorEmail)
            Text("·").foregroundStyle(theme.colors.textQuaternary)
            Text(preferences.dateDisplayMode.format(commit.authorDate))
                .textRole(.callout)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: Spacing.s8)
            Button {
                NSPasteboard.general.declareTypes([.string], owner: nil)
                NSPasteboard.general.setString(commit.sha, forType: .string)
            } label: {
                HStack(spacing: Spacing.s4) {
                    Text(commit.shortSha).textRole(.monoSmall)
                    Image(systemName: "doc.on.doc").font(.system(size: 10)).accessibilityHidden(true)
                }
                .foregroundStyle(theme.colors.textSecondary)
                .padding(.horizontal, Spacing.s6)
                .frame(height: 22)
                .background(RoundedRectangle(cornerRadius: Radius.controlSmall).fill(theme.colors.fillControl))
            }
            .buttonStyle(.plain)
            .help("Copy full SHA")
            .accessibilityLabel("Copy full SHA \(commit.shortSha)")
        }
    }

    @ViewBuilder
    private var parentLine: some View {
        if !commit.parentShas.isEmpty {
            HStack(spacing: Spacing.s6) {
                Text(commit.parentShas.count > 1 ? "Parents" : "Parent")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                ForEach(commit.parentShas, id: \.self) { parent in
                    Button(String(parent.prefix(7))) {
                        if let match = viewModel.commits.first(where: { $0.sha == parent }) {
                            viewModel.selectedCommitId = match.sha
                        }
                    }
                    .buttonStyle(.plain)
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.accent)
                    .help("Select parent \(parent.prefix(7))")
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitDetailColumn(commit: .preview, viewModel: .preview)
        .previewAppState(.preview)
        .padding()
        .frame(width: 480, height: 720)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
