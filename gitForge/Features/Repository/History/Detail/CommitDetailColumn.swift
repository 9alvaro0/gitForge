import SwiftUI
import AppKit

/// The commit in History's inspector, in sections (audit M5, phase 2.3): a
/// header that stays put (subject, author and date, SHA, the "…" actions
/// menu), the details that fold away (parents, signature and CI, message),
/// and the changed files, which scroll on their own. The diff under it gets
/// the height without anything falling out of reach.
struct CommitDetailColumn: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme
    @Environment(\.appPreferences) private var preferences

    /// Details unfolded; one choice for every commit, kept across launches.
    @AppStorage(HistoryInspectorMetrics.detailsExpandedKey) private var detailsExpanded = true
    /// The selected commit's CI, `nil` until known or when the host has none.
    @State private var checks: [CICheck]?
    /// The column's height, which the unfolded details take a share of.
    @State private var columnHeight: CGFloat = 0

    private var detail: CommitDetail? { viewModel.history.detailCache[commit.sha] }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Spacing.s16)
                .padding(.top, Spacing.s12)
                .padding(.bottom, Spacing.s8)
            if hasDetails {
                details
            }
            CommitFilesSection(commit: commit, viewModel: viewModel)
                .padding(.top, Spacing.s8)
                .frame(maxHeight: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { columnHeight = $0 }
        .task(id: commit.sha) {
            _ = await viewModel.history.detail(for: commit)
        }
        .task(id: commit.sha) {
            checks = nil
            // Arrow-keying through History shouldn't fire a request per row.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let loaded = await viewModel.pullRequests.commitChecks(sha: commit.sha)
            guard !Task.isCancelled else { return }
            checks = loaded
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s8) {
                Text(commit.subject)
                    .textRole(.title)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(commit.subject)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CommitActionsMenu(commit: commit, viewModel: viewModel)
            }
            authorLine
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
            .fixedSize()
            .help("Copy full SHA")
            .accessibilityLabel("Copy full SHA \(commit.shortSha)")
        }
    }

    // MARK: Details

    private var hasTrust: Bool {
        CommitTrustLine.hasContent(signature: detail?.signature, checks: checks)
    }

    private var bodyText: String? {
        guard let text = detail?.bodyText, !text.isEmpty else { return nil }
        return text
    }

    private var hasDetails: Bool {
        !commit.parentShas.isEmpty || hasTrust || bodyText != nil
    }

    /// A disclosure row, then (unfolded) the details, scrolling within a
    /// share of the column when the message is long.
    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Motion.fast) { detailsExpanded.toggle() }
            } label: {
                HStack(spacing: Spacing.s6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(detailsExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text("Details")
                        .textRole(.caption, weight: .semibold)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.horizontal, Spacing.s16)
                .frame(height: 24)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("Parents, signature, CI and message")
            .accessibilityValue(detailsExpanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
            if detailsExpanded {
                ViewThatFits(in: .vertical) {
                    detailsContent
                    InspectorScrollArea(horizontalMargin: 0) { detailsContent }
                        .frame(minHeight: HistoryInspectorMetrics.minDetailsScrollHeight)
                }
                .frame(maxHeight: HistoryInspectorMetrics.detailsCap(columnHeight: columnHeight), alignment: .top)
            }
        }
    }

    private var detailsContent: some View {
        VStack(alignment: .leading, spacing: Spacing.s8) {
            parentLine
            if hasTrust {
                CommitTrustLine(signature: detail?.signature, checks: checks)
            }
            if let bodyText {
                Text(CommitMessage.reflow(bodyText))
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, Spacing.s16)
        .padding(.top, Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var parentLine: some View {
        if !commit.parentShas.isEmpty {
            HStack(spacing: Spacing.s6) {
                Text(commit.parentShas.count > 1 ? String(localized: "Parents") : String(localized: "Parent"))
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                ForEach(commit.parentShas, id: \.self) { parent in
                    Button(String(parent.prefix(7))) {
                        if let match = viewModel.history.commits.first(where: { $0.sha == parent }) {
                            viewModel.history.selectedCommitId = match.sha
                        }
                    }
                    .buttonStyle(.plain)
                    .textRole(.monoSmall)
                    .foregroundStyle(theme.colors.accent)
                    .help("Select parent \(parent.prefix(7))")
                    .accessibilityLabel("Select parent commit \(parent.prefix(7))")
                    .disabled(!viewModel.history.commits.contains { $0.sha == parent })
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CommitDetailColumn(commit: .preview, viewModel: .preview)
        .previewAppState(.preview)
        .frame(width: 480, height: 520)
        .background(theme.colors.bgElevated)
        .appTheme(theme)
}
