import SwiftUI

/// `.gf-view-clone` — Clone repository form, "My repos" (the repos of a
/// connected GitHub/GitLab account), and recent repos list. Talks to `AppState.startClone` /
/// `cancelClone` and observes `cloneState` for live progress.
struct CloneView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    @State private var sourceURL: String = ""
    @State private var localPath: String = ""
    @State private var branch: String = ""
    /// Tracks the most recent value produced by the autoderive so we can tell
    /// whether the user has edited the path manually. If `localPath` no longer
    /// matches `lastAutoDerived`, we stop overwriting it from URL changes.
    @State private var lastAutoDerived: String = ""

    @State private var sourceTab: SourceTab = .url
    /// The repo picked in "My repos" and the account it was listed with;
    /// the clone uses that account while the URL field still holds its URL.
    @State private var browsedURL: String?
    @State private var browsedAccountId: UUID?

    enum SourceTab: Hashable { case local, url, github, gitlab }

    /// Last parent directory the user picked / cloned into. Persisted so the
    /// next clone session pre-fills with the same parent and only the leaf
    /// name changes — same UX as GitKraken/Sourcetree.
    @AppStorage("gitForge.clone.lastParentDir") private var lastParentDir: String = ""

    private var repositories: [Repository] { appState.catalog.repositories }
    private var isCloning: Bool { appState.clone.isCloning }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxxxl) {
                    sourceTabs
                    sourceTabContent
                    recentSection
                }
                .padding(DesignTokens.Spacing.xxxxl)
                .frame(maxWidth: 720, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
        .navigationTitle("Add a repository")
    }

    private var sourceTabs: some View {
        SegmentedControl<SourceTab>(
            [(.local, "Local"), (.url, "URL"), (.github, "GitHub"), (.gitlab, "GitLab")],
            selection: $sourceTab
        )
        .frame(maxWidth: 380, alignment: .leading)
    }

    @ViewBuilder
    private var sourceTabContent: some View {
        switch sourceTab {
        case .local:
            localCard
        case .url:
            cloneCard
        case .github:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                RemoteRepoPicker(kind: .github) { repo, accountId in
                    selectRemoteRepo(repo, accountId: accountId)
                }
                if isCloning {
                    cloningPanel
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        case .gitlab:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                RemoteRepoPicker(kind: .gitlab) { repo, accountId in
                    selectRemoteRepo(repo, accountId: accountId)
                }
                if isCloning {
                    cloningPanel
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    /// Filling the clone form from a "My repos" row: HTTPS, so the account
    /// it was listed with can sign the clone (spec §7.4). Switches to the
    /// URL tab so the user sees what's about to be cloned.
    private func selectRemoteRepo(_ repo: RemoteRepoSummary, accountId: UUID) {
        sourceURL = repo.httpsURL
        browsedURL = repo.httpsURL
        browsedAccountId = accountId
        autofillPath(from: sourceURL)
        sourceTab = .url
    }

    private var cloningPanel: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            if case let .running(stage, percent) = appState.clone.cloneState {
                progressRow(stage: stage, percent: percent)
            }
            HStack {
                Spacer()
                GFButton(title: "Cancel", style: .secondary) {
                    appState.clone.cancel()
                }
            }
        }
        .padding(DesignTokens.Spacing.xxxl)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    /// Add an existing repo from disk — no clone, just a pointer. Drops the
    /// user straight into NSOpenPanel via the same `presentOpenRepositoryPanel`
    /// the sidebar's `+` menu uses, so behavior stays consistent across entry
    /// points.
    private var localCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            HStack(spacing: DesignTokens.Spacing.lg) {
                GFIcon(kind: .folder, size: 22, stroke: theme.palette.fg2)
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Open a folder on this Mac")
                        .font(AppFont.sans(FontSize.lg, weight: .semibold))
                        .foregroundStyle(theme.palette.fg1)
                    Text("Add an existing git repository without cloning it again.")
                        .font(AppFont.sans(FontSize.smPlus))
                        .foregroundStyle(theme.palette.fg3)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Spacer()
                GFButton(title: "Choose folder…", style: .primary) {
                    Task { await appState.presentOpenRepositoryPanel() }
                }
            }
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(maxWidth: 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
            field(label: "Source URL", hint: urlHint) {
                GFTextField(placeholder: "git@github.com:owner/repo.git", text: $sourceURL)
                    .onChange(of: sourceURL) { _, newValue in
                        autofillPath(from: newValue)
                    }
            }
            if let suggestion = instanceSuggestion {
                GFButton(title: "Add \(suggestion.host) as a \(suggestion.kind.label) instance…", size: .small) {
                    appState.ui.addInstanceRequest = AddInstanceRequest(kind: suggestion.kind, url: "https://\(suggestion.host)")
                }
            }
            field(label: "Local path", hint: pathHint) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    GFTextField(placeholder: "~/code/repo", text: $localPath)
                    GFButton(title: "Choose…") { Task { await pickPath() } }
                }
            }
            field(label: "Branch (optional)") {
                GFTextField(placeholder: "default branch", text: $branch)
            }
            if case let .running(stage, percent) = appState.clone.cloneState {
                progressRow(stage: stage, percent: percent)
            }
            HStack(spacing: DesignTokens.Spacing.md) {
                Spacer()
                if isCloning {
                    GFButton(title: "Cancel", style: .secondary) {
                        appState.clone.cancel()
                    }
                }
                GFButton(title: isCloning ? "Cloning…" : "Clone",
                         style: .primary,
                         disabled: isCloning || !canClone) {
                    clone()
                }
            }
            .padding(.top, DesignTokens.Spacing.xs)
        }
        .padding(DesignTokens.Spacing.huge)
        .frame(maxWidth: 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
    }

    @ViewBuilder
    private func field<C: View>(label: String, hint: FieldHint? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(label)
                    .font(AppFont.sans(FontSize.sm, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                if let hint {
                    GFIcon(kind: hint.kind.icon, size: DesignTokens.IconSize.xs, stroke: hint.kind.tint)
                    Text(hint.message)
                        .font(AppFont.sans(FontSize.xs))
                        .foregroundStyle(hint.kind.tint)
                        .lineLimit(1)
                }
            }
            content()
        }
    }

    private struct FieldHint {
        enum Kind {
            case ok, warn, bad
            var icon: GFIconKind {
                switch self {
                case .ok:   return .check
                case .warn: return .warn
                case .bad:  return .x
                }
            }
            var tint: Color {
                switch self {
                case .ok:   return .green
                case .warn: return .orange
                case .bad:  return .red
                }
            }
        }
        let kind: Kind
        let message: String
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("RECENT")
                .font(.system(size: FontSize.sm, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            ForEach(repositories) { repo in
                HStack(spacing: DesignTokens.Spacing.lg) {
                    RepoMark(letter: orgInitial(repo))
                    Text("\(orgName(repo))/\(repo.name)")
                        .font(AppFont.mono(FontSize.md, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                        .frame(width: 220, alignment: .leading)
                    Text(repo.path)
                        .font(AppFont.mono(FontSize.sm, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg3)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    GFButton(title: "Open", size: .small) {
                        Task { await appState.activate(repo) }
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.xl)
                .padding(.vertical, DesignTokens.Spacing.md)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: DesignTokens.Stroke.regular))
            }
        }
    }

    private func clone() {
        // Persist the parent so next time we land on the same default.
        let parent = (localPath as NSString).deletingLastPathComponent
        if !parent.isEmpty { lastParentDir = parent }
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.startClone(
            url: sourceURL,
            path: localPath,
            branch: branch.isEmpty ? nil : branch,
            accountId: trimmed == browsedURL ? browsedAccountId : nil
        )
    }

    @ViewBuilder
    private func progressRow(stage: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(stage)
                    .font(AppFont.mono(FontSize.sm, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
                Spacer()
                Text("\(Int(percent * 100))%")
                    .font(AppFont.mono(FontSize.sm, family: theme.monoFont).monospacedDigit())
                    .foregroundStyle(theme.palette.fg2)
            }
            ProgressView(value: percent)
                .progressViewStyle(.linear)
                .tint(theme.palette.accent)
        }
        .padding(.top, DesignTokens.Spacing.xs)
    }

    private func pickPath() async {
        guard let parent = await appState.pickDirectoryPath(prompt: "Choose parent directory") else { return }
        lastParentDir = parent
        let leaf = inferRepoName(from: sourceURL) ?? "repo"
        let composed = "\(parent)/\(leaf)"
        localPath = composed
        lastAutoDerived = composed
    }

    private func inferRepoName(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.split(separator: "/").last else { return nil }
        var name = String(last)
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name.isEmpty ? nil : name
    }

    /// Compute the path we'd suggest for `sourceURL` and apply it only if the
    /// user hasn't manually edited the field — the sentinel `lastAutoDerived`
    /// tells us "the value in the field is exactly what we put there last".
    private func autofillPath(from url: String) {
        guard let leaf = inferRepoName(from: url) else { return }
        // Empty `lastParentDir` ≠ empty placeholder; only autofill when we
        // have a parent to compose with, otherwise we'd suggest just the leaf.
        let parent = lastParentDir.isEmpty
            ? ("~/code" as NSString).expandingTildeInPath
            : lastParentDir
        let composed = "\(parent)/\(leaf)"
        if localPath.isEmpty || localPath == lastAutoDerived {
            localPath = composed
            lastAutoDerived = composed
        }
    }

    // MARK: - Validation

    private var urlHint: FieldHint? {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if RemoteHost.parse(trimmed, instances: appState.accounts.instances) != nil {
            return FieldHint(kind: .ok, message: "Recognized")
        }
        if let suggestion = instanceSuggestion {
            return FieldHint(kind: .warn, message: "\(suggestion.host) isn't an added instance")
        }
        // Looks like a git URL (ends in .git or contains :) but unknown host.
        if trimmed.hasSuffix(".git") || trimmed.contains(":") || trimmed.hasPrefix("http") {
            return FieldHint(kind: .warn, message: "Unknown host — clone may still work")
        }
        return FieldHint(kind: .bad, message: "Doesn't look like a git URL")
    }

    private var instanceSuggestion: InstanceSuggestion? {
        RemoteHost.suggestedInstance(forRemoteURL: sourceURL, instances: appState.accounts.instances)
    }

    private var pathHint: FieldHint? {
        let trimmed = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return FieldHint(kind: .bad, message: "Destination already exists")
        }
        let parent = (expanded as NSString).deletingLastPathComponent
        if parent.isEmpty || !FileManager.default.fileExists(atPath: parent) {
            return FieldHint(kind: .warn, message: "Parent will be created")
        }
        return FieldHint(kind: .ok, message: "Available")
    }

    private var canClone: Bool {
        guard !sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if pathHint?.kind == .bad { return false }
        return true
    }

    private func orgName(_ repo: Repository) -> String { repo.url.deletingLastPathComponent().lastPathComponent }
    private func orgInitial(_ repo: Repository) -> String { String(orgName(repo).prefix(1)) }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CloneView()
        .previewAppState(.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
