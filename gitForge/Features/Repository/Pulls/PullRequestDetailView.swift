import SwiftUI
import AppKit

/// `.gf-view-pulls-detail` — detail view for a single PR/MR. Tabs:
/// Overview (description, reviewers, labels, CI status) / Commits / Files.
struct PullRequestDetailView: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme
    @State private var tab: Tab = .overview

    enum Tab: String, Hashable, CaseIterable, Identifiable {
        case overview, commits, files
        var id: String { rawValue }
        var label: String {
            switch self {
            case .overview: "Overview"
            case .commits:  "Commits"
            case .files:    "Files"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        if let pr = viewModel.selectedPullRequest {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    GFButton(title: "← Back", size: .small) {
                        viewModel.closePullRequestDetail()
                    }
                    Spacer()
                    if let url = pr.webURL {
                        ToolButton(.ext, label: "Open in browser") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PullRequestStatePill(state: pr.state)
                    Text(pr.title)
                        .font(AppFont.sans(16, weight: .semibold))
                        .foregroundStyle(theme.palette.fg1)
                        .lineLimit(2)
                    MonoText("#\(pr.number)", dim: true)
                }
                HStack(spacing: 6) {
                    if let author = pr.authorLogin {
                        MonoText("@\(author)", dim: true)
                        Text("·").foregroundStyle(theme.palette.fg4)
                    }
                    MonoText(pr.sourceBranch, dim: true)
                    Text("→").foregroundStyle(theme.palette.fg4)
                    MonoText(pr.targetBranch, dim: true)
                    if let updated = pr.updatedAt {
                        Text("·").foregroundStyle(theme.palette.fg4)
                        MonoText(relativeDate(updated), dim: true)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.palette.bg2)
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.palette.lineStrong).frame(height: 1)
            }
        }
    }

    private var tabBar: some View {
        HStack {
            SegmentedControl<Tab>(
                Tab.allCases.map { ($0, $0.label) },
                selection: $tab
            )
            Spacer()
            if viewModel.pullRequestDetailLoading {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(theme.palette.bg1)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.line).frame(height: 1)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let error = viewModel.pullRequestDetailError, viewModel.pullRequestDetail == nil {
                EmptyState(icon: .warn, title: "Couldn't load detail", subtitle: error) {
                    GFButton(title: "Retry", style: .primary) {
                        Task { await viewModel.loadPullRequestDetail() }
                    }
                }
            } else {
                switch tab {
                case .overview: OverviewTab(detail: viewModel.pullRequestDetail)
                case .commits:  CommitsTab(commits: viewModel.pullRequestCommits, loading: viewModel.pullRequestDetailLoading)
                case .files:    FilesTab(files: viewModel.pullRequestFiles, loading: viewModel.pullRequestDetailLoading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - State pill

private struct PullRequestStatePill: View {
    let state: PullRequest.State
    @Environment(\.appTheme) private var theme

    var body: some View {
        let p = theme.palette
        let (label, fg, bg): (String, Color, Color) = {
            switch state {
            case .open:   return ("OPEN",   p.ok,   p.ok.opacity(0.14))
            case .merged: return ("MERGED", p.info, p.info.opacity(0.14))
            case .closed: return ("CLOSED", p.del,  p.del.opacity(0.14))
            case .draft:  return ("DRAFT",  p.fg3,  p.bg3)
            }
        }()
        Text(label)
            .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: 3).fill(bg))
    }
}

// MARK: - Overview tab

private struct OverviewTab: View {
    let detail: PullRequestDetail?
    @Environment(\.appTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail {
                    metaRow(detail)
                    descriptionBlock(detail)
                    if !detail.reviewers.isEmpty { reviewersBlock(detail) }
                    if !detail.labels.isEmpty { labelsBlock(detail) }
                } else {
                    placeholderContent
                        .skeleton(true)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var placeholderContent: some View {
        FlowLayout(spacing: 8) {
            Text("CI: All checks passed")
                .font(AppFont.sans(11))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg3))
            Text("Mergeable")
                .font(AppFont.sans(11))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg3))
        }

        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Description")
            Text("Adds the PR/MR integration with the new detail view, including overview, commits, and files tabs.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg2)
            Text("Each tab shares state with the parent so navigating between them is instantaneous.")
                .font(AppFont.sans(12))
                .foregroundStyle(theme.palette.fg2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))

        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Reviewers")
            FlowLayout(spacing: 6) {
                ForEach(["@reviewer-one", "@reviewer-two", "@reviewer-three"], id: \.self) { name in
                    MonoText(name)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg2))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))

        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Labels")
            FlowLayout(spacing: 6) {
                ForEach(["feature", "phase-2", "needs-review"], id: \.self) { name in
                    Text(name)
                        .font(AppFont.sans(11))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .foregroundStyle(theme.palette.fg2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg2))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func metaRow(_ detail: PullRequestDetail) -> some View {
        FlowLayout(spacing: 8) {
            if let ci = detail.ciStatus {
                ciPill(ci)
            }
            mergeabilityPill(detail.mergeable)
        }
    }

    @ViewBuilder
    private func ciPill(_ ci: CIStatus) -> some View {
        let p = theme.palette
        let (fg, bg): (Color, Color) = {
            switch ci.state {
            case .success:  (p.ok,   p.ok.opacity(0.14))
            case .failure:  (p.del,  p.del.opacity(0.14))
            case .pending:  (p.mod,  p.mod.opacity(0.14))
            case .canceled, .unknown: (p.fg3, p.bg3)
            }
        }()
        let content = HStack(spacing: 4) {
            Text("CI:")
                .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
                .foregroundStyle(fg)
            Text(ci.label)
                .font(AppFont.sans(11))
                .foregroundStyle(fg)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 3).fill(bg))
        if let url = ci.webURL {
            Button { NSWorkspace.shared.open(url) } label: { content.contentShape(.rect(cornerRadius: 3)) }.buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private func mergeabilityPill(_ mergeable: Bool?) -> some View {
        let p = theme.palette
        let (text, fg, bg): (String, Color, Color) = {
            switch mergeable {
            case .some(true):  return ("Mergeable", p.ok, p.ok.opacity(0.14))
            case .some(false): return ("Has conflicts", p.del, p.del.opacity(0.14))
            case .none:        return ("Mergeability unknown", p.fg3, p.bg3)
            }
        }()
        Text(text)
            .font(AppFont.sans(11))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(fg)
            .background(RoundedRectangle(cornerRadius: 3).fill(bg))
    }

    @ViewBuilder
    private func descriptionBlock(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Description")
            if let body = detail.descriptionMarkdown, !body.isEmpty {
                MarkdownView(source: body)
            } else {
                Text("No description provided.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func reviewersBlock(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Reviewers")
            FlowLayout(spacing: 6) {
                ForEach(detail.reviewers) { r in
                    HStack(spacing: 4) {
                        if r.approved {
                            Text("✓")
                                .font(AppFont.mono(10, weight: .bold, family: theme.monoFont))
                                .foregroundStyle(theme.palette.ok)
                        }
                        MonoText("@\(r.login)")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg2))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func labelsBlock(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Labels")
            FlowLayout(spacing: 6) {
                ForEach(detail.labels, id: \.self) { name in
                    Text(name)
                        .font(AppFont.sans(11))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(theme.palette.fg2)
                        .background(RoundedRectangle(cornerRadius: 3).fill(theme.palette.bg2))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(theme.palette.fg3)
    }

    private func markdownAttributed(_ raw: String) -> AttributedString {
        // `.full` interprets the whole document. If parsing fails we fall back
        // to a plain-text AttributedString so the description always renders.
        if let parsed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
        ) {
            return parsed
        }
        return AttributedString(raw)
    }
}

// MARK: - Commits tab

private struct CommitsTab: View {
    let commits: [PullRequestCommit]
    let loading: Bool
    @Environment(\.appTheme) private var theme

    var body: some View {
        if commits.isEmpty {
            if loading {
                placeholderList
            } else {
                EmptyState(icon: .graph, title: "No commits", subtitle: nil) { EmptyView() }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(commits) { commit in
                        commitRow(commit)
                    }
                }
                .padding(18)
            }
        }
    }

    private static let placeholderSubjects = [
        "feat: add pull request detail view",
        "refactor: split provider-specific mappers",
        "fix: handle nil reviewer avatar URLs",
        "chore: bump dependency versions",
        "test: cover empty merge request payloads",
    ]

    private var placeholderList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { index in
                    placeholderRow(index: index)
                }
            }
            .padding(18)
        }
        .skeleton(true)
    }

    @ViewBuilder
    private func placeholderRow(index: Int) -> some View {
        let subject = Self.placeholderSubjects[index % Self.placeholderSubjects.count]
        HStack(spacing: 12) {
            MonoText("abc1234", color: theme.palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(subject)
                    .font(AppFont.sans(12.5))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    MonoText("9alvaro0", dim: true)
                    Text("·").foregroundStyle(theme.palette.fg4)
                    MonoText("2h ago", dim: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func commitRow(_ commit: PullRequestCommit) -> some View {
        HStack(spacing: 12) {
            MonoText(commit.shortSha, color: theme.palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.subject)
                    .font(AppFont.sans(12.5))
                    .foregroundStyle(theme.palette.fg1)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    if let author = commit.authorName {
                        MonoText(author, dim: true)
                    }
                    if let date = commit.authorDate {
                        Text("·").foregroundStyle(theme.palette.fg4)
                        MonoText(relativeDate(date), dim: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

// MARK: - Files tab

private struct FilesTab: View {
    let files: [PullRequestFileChange]
    let loading: Bool

    @Environment(\.appTheme) private var theme
    @Environment(AppState.self) private var appState
    @State private var selectedPath: String?
    @State private var diffViewMode: DiffPane.ViewMode = .unified

    var body: some View {
        if files.isEmpty {
            if loading {
                placeholderList
            } else {
                EmptyState(icon: .diff, title: "No files changed", subtitle: nil) { EmptyView() }
            }
        } else {
            HStack(spacing: 0) {
                fileList
                    .frame(width: DesignTokens.Pulls.listWidth)
                    .frame(maxHeight: .infinity)
                    .background(theme.palette.bg1)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(theme.palette.line).frame(width: 1)
                    }
                diffPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                if selectedPath == nil { selectedPath = files.first?.path }
            }
            .onChange(of: files.map(\.path)) { _, _ in
                if let current = selectedPath, !files.contains(where: { $0.path == current }) {
                    selectedPath = files.first?.path
                }
            }
        }
    }

    private var fileList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(files) { file in
                    fileRow(file)
                }
            }
        }
    }

    private static let placeholderPaths = [
        "Sources/Features/PullRequest/PullRequestDetailView.swift",
        "Sources/Core/Models/PullRequest.swift",
        "Sources/Core/RemoteHosting/GitHubProvider.swift",
        "Sources/Core/RemoteHosting/GitLabProvider.swift",
        "Sources/DesignSystem/Components/Skeleton.swift",
        "README.md",
        "Tests/PullRequestTests.swift",
    ]

    private var placeholderList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    placeholderRow(index: index)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.palette.bg1)
        .skeleton(true)
    }

    @ViewBuilder
    private func placeholderRow(index: Int) -> some View {
        let path = Self.placeholderPaths[index % Self.placeholderPaths.count]
        HStack(spacing: 8) {
            StatusTag(kind: .modified)
            Text(path)
                .font(AppFont.mono(11.5, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg2)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            MonoText("+10", color: theme.palette.add)
            MonoText("−4", color: theme.palette.del)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func fileRow(_ file: PullRequestFileChange) -> some View {
        let isSelected = file.path == selectedPath
        Button {
            selectedPath = file.path
        } label: {
            HStack(spacing: 8) {
                StatusTag(kind: StatusTag.Kind(prFileStatus: file.status))
                Text(file.path)
                    .font(AppFont.mono(11.5, family: theme.monoFont))
                    .foregroundStyle(isSelected ? theme.palette.fg1 : theme.palette.fg2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if file.additions > 0 {
                    MonoText("+\(file.additions)", color: theme.palette.add)
                }
                if file.deletions > 0 {
                    MonoText("−\(file.deletions)", color: theme.palette.del)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? theme.palette.bg3 : Color.clear)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var diffPane: some View {
        let selected = files.first(where: { $0.path == selectedPath })
        let hunks: [DiffHunk] = {
            guard let patch = selected?.patch, !patch.isEmpty else { return [] }
            return DiffParser.parse(patch)
        }()
        DiffPane(file: selected?.path, hunks: hunks, viewMode: $diffViewMode)
    }
}

private extension StatusTag.Kind {
    init(prFileStatus: PullRequestFileChange.Status) {
        switch prFileStatus {
        case .added:    self = .added
        case .modified: self = .modified
        case .deleted:  self = .deleted
        case .renamed:  self = .renamed
        case .copied:   self = .copied
        case .other:    self = .modified
        }
    }
}

#Preview("Detail — Loading") {
    @Previewable @State var theme = AppTheme()
    let vm = RepositoryViewModel.preview
    vm.pullRequestsHost = RemoteHost(provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge")
    vm.selectedPullRequest = PullRequest.previewSamples.first
    vm.pullRequestDetail = nil
    vm.pullRequestCommits = []
    vm.pullRequestFiles = []
    vm.pullRequestDetailLoading = true
    return PullRequestDetailView(viewModel: vm)
        .environment(AppState.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}

#Preview("Detail") {
    @Previewable @State var theme = AppTheme()
    let vm = RepositoryViewModel.preview
    vm.pullRequestsHost = RemoteHost(provider: .github, host: "github.com", owner: "9alvaro0", repo: "gitForge")
    vm.selectedPullRequest = PullRequest.previewSamples.first
    vm.pullRequestDetail = PullRequestDetail(
        pull: PullRequest.previewSamples.first!,
        descriptionMarkdown: "Adds the **PR/MR** integration with `Phase 2` detail view.\n\n- Description\n- Commits\n- Files",
        labels: ["feature", "phase-2"],
        reviewers: [.init(login: "reviewer1", approved: true), .init(login: "reviewer2", approved: false)],
        assignees: ["9alvaro0"],
        mergeable: true,
        ciStatus: CIStatus(state: .success, description: "All checks passed", webURL: nil)
    )
    vm.pullRequestCommits = [
        PullRequestCommit(sha: "abc1234abcdef", subject: "feat: add PR detail view", authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -3600)),
        PullRequestCommit(sha: "def5678abcdef", subject: "refactor: split provider", authorName: "9alvaro0", authorDate: Date(timeIntervalSinceNow: -7200)),
    ]
    vm.pullRequestFiles = [
        PullRequestFileChange(path: "Sources/Foo.swift", oldPath: nil, status: .modified, additions: 42, deletions: 5,
                              patch: "@@ -1,3 +1,5 @@\n line1\n-old\n+new\n+added\n line3"),
        PullRequestFileChange(path: "README.md", oldPath: nil, status: .added, additions: 10, deletions: 0,
                              patch: "@@ -0,0 +1,3 @@\n+# Title\n+\n+Body"),
    ]
    return PullRequestDetailView(viewModel: vm)
        .environment(AppState.preview)
        .frame(width: 1200, height: 720)
        .appTheme(theme)
}
