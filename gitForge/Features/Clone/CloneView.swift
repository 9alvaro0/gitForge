import SwiftUI

/// `.gf-view-clone` — Clone repository form, "My repos" picker for GitHub/
/// GitLab, and recent repos list. Talks to `AppState.startClone` /
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

    enum SourceTab: Hashable { case local, url, github, gitlab }

    /// Last parent directory the user picked / cloned into. Persisted so the
    /// next clone session pre-fills with the same parent and only the leaf
    /// name changes — same UX as GitKraken/Sourcetree.
    @AppStorage("gitForge.clone.lastParentDir") private var lastParentDir: String = ""

    private var repositories: [Repository] { appState.catalog.repositories }
    private var isCloning: Bool { appState.clone.isCloning }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.none) {
            ContentHeader(title: "Add a repository")
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
                RemoteRepoPicker(provider: .github, availableHosts: hostsFor(.github)) { repo in
                    selectRemoteRepo(repo)
                }
                if isCloning {
                    cloningPanel
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        case .gitlab:
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxl) {
                RemoteRepoPicker(provider: .gitlab, availableHosts: hostsFor(.gitlab)) { repo in
                    selectRemoteRepo(repo)
                }
                if isCloning {
                    cloningPanel
                }
            }
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    /// Hosts in the Keychain that match `provider`'s naming heuristic, plus
    /// the canonical default. Filters by substring (`github` / `gitlab`) so
    /// self-hosted instances like `gitlab.example.com` show up automatically.
    /// The default is appended so the user can still browse the public host
    /// even when they only have tokens for self-hosted ones.
    private func hostsFor(_ provider: RemoteProvider) -> [String] {
        let needle: String = {
            switch provider {
            case .github: return "github"
            case .gitlab: return "gitlab"
            }
        }()
        let canonical: String = {
            switch provider {
            case .github: return "github.com"
            case .gitlab: return "gitlab.com"
            }
        }()
        let stored = RemoteCredentialsStore.shared.knownHosts()
            .filter { $0.lowercased().contains(needle) }
        // Put the canonical host last so users with a self-hosted token land
        // on theirs by default — that's the one most likely to actually work.
        var result = stored
        if !result.contains(canonical) { result.append(canonical) }
        return result
    }

    /// Filling the clone form from a remote repo row: prefer SSH if available
    /// (matches what most devs have configured for push), otherwise HTTPS.
    /// Switches to the URL tab so the user sees what's about to be cloned and
    /// can tweak the path or branch before confirming.
    private func selectRemoteRepo(_ repo: RemoteRepoSummary) {
        sourceURL = repo.sshURL ?? repo.httpsURL
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
                        .font(AppFont.sans(13, weight: .semibold))
                        .foregroundStyle(theme.palette.fg1)
                    Text("Add an existing git repository without cloning it again.")
                        .font(AppFont.sans(11.5))
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
                    .font(AppFont.sans(11, weight: .medium))
                    .foregroundStyle(theme.palette.fg3)
                if let hint {
                    Image(systemName: hint.kind.iconName)
                        .font(.system(size: FontSize.caption, weight: .semibold))
                        .foregroundStyle(hint.kind.tint)
                    Text(hint.message)
                        .font(AppFont.sans(10.5))
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
            var iconName: String {
                switch self {
                case .ok:   return "checkmark.circle.fill"
                case .warn: return "exclamationmark.triangle.fill"
                case .bad:  return "xmark.octagon.fill"
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
                .font(.system(size: FontSize.footnote, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            ForEach(repositories) { repo in
                HStack(spacing: DesignTokens.Spacing.lg) {
                    RepoMark(letter: orgInitial(repo))
                    Text("\(orgName(repo))/\(repo.name)")
                        .font(AppFont.mono(12, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg1)
                        .frame(width: 220, alignment: .leading)
                    Text(repo.path)
                        .font(AppFont.mono(11, family: theme.monoFont))
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
        appState.startClone(
            url: sourceURL,
            path: localPath,
            branch: branch.isEmpty ? nil : branch
        )
    }

    @ViewBuilder
    private func progressRow(stage: String, percent: Double) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Text(stage)
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg2)
                Spacer()
                Text("\(Int(percent * 100))%")
                    .font(AppFont.mono(11, family: theme.monoFont).monospacedDigit())
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
        if let host = RemoteHost.parse(trimmed) { return host.repo }
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
        if RemoteHost.parse(trimmed) != nil { return FieldHint(kind: .ok, message: "Recognized") }
        // Looks like a git URL (ends in .git or contains :) but unknown host.
        if trimmed.hasSuffix(".git") || trimmed.contains(":") || trimmed.hasPrefix("http") {
            return FieldHint(kind: .warn, message: "Unknown host — clone may still work")
        }
        return FieldHint(kind: .bad, message: "Doesn't look like a git URL")
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
