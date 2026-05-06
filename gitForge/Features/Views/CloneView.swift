import SwiftUI

/// `.gf-view-clone` — Clone repository form + recent repos list. Talks to
/// `AppState.cloneRepository` directly.
struct CloneView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.appTheme) private var theme

    @State private var sourceURL: String = ""
    @State private var localPath: String = ""
    @State private var branch: String = ""

    private var repositories: [Repository] { appState.repositories }
    private var isCloning: Bool { appState.isCloning }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Clone a repository")
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    cloneCard
                    recentSection
                }
                .padding(18)
                .frame(maxWidth: 720, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    private var cloneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            field(label: "Source URL") {
                GFTextField(placeholder: "git@github.com:owner/repo.git", text: $sourceURL)
            }
            field(label: "Local path") {
                HStack(spacing: 6) {
                    GFTextField(placeholder: "~/code/repo", text: $localPath)
                    GFButton(title: "Choose…") { Task { await pickPath() } }
                }
            }
            field(label: "Branch (optional)") {
                GFTextField(placeholder: "default branch", text: $branch)
            }
            HStack(spacing: 8) {
                if isCloning {
                    ProgressView().controlSize(.small)
                    Text("Cloning…")
                        .font(AppFont.mono(11, family: theme.monoFont))
                        .foregroundStyle(theme.palette.fg2)
                }
                Spacer()
                GFButton(title: isCloning ? "Cloning…" : "Clone",
                         style: .primary,
                         disabled: isCloning || sourceURL.isEmpty || localPath.isEmpty) {
                    Task { await clone() }
                }
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: 1))
    }

    @ViewBuilder
    private func field<C: View>(label: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(AppFont.sans(11, weight: .medium))
                .foregroundStyle(theme.palette.fg3)
            content()
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            ForEach(repositories) { repo in
                HStack(spacing: 10) {
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
            }
        }
    }

    private func clone() async {
        await appState.cloneRepository(
            url: sourceURL,
            path: localPath,
            branch: branch.isEmpty ? nil : branch
        )
    }

    private func pickPath() async {
        guard let parent = await appState.pickDirectoryPath(prompt: "Choose parent directory") else { return }
        let leaf = inferRepoName(from: sourceURL) ?? "repo"
        localPath = "\(parent)/\(leaf)"
    }

    private func inferRepoName(from url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.split(separator: "/").last else { return nil }
        var name = String(last)
        if name.hasSuffix(".git") { name.removeLast(4) }
        return name.isEmpty ? nil : name
    }

    private func orgName(_ repo: Repository) -> String { repo.url.deletingLastPathComponent().lastPathComponent }
    private func orgInitial(_ repo: Repository) -> String { String(orgName(repo).prefix(1)) }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CloneView()
        .environment(AppState.preview)
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
