import SwiftUI

/// `.gf-view-clone` — Clone repository form + recent repos list.
struct CloneView: View {
    let repositories: [Repository]
    var onClone: (String, String, String) -> Void
    var onPickPath: () -> Void
    var onOpenRepo: (Repository) -> Void

    @State private var sourceURL: String = "git@github.com:acme/api-core.git"
    @State private var localPath: String = "~/code/api-core"
    @State private var branch: String = "main"

    @Environment(\.appTheme) private var theme

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
                GFTextField(placeholder: "git@…", text: $sourceURL)
            }
            field(label: "Local path") {
                HStack(spacing: 6) {
                    GFTextField(placeholder: "~/…", text: $localPath)
                    GFButton(title: "Choose…", action: onPickPath)
                }
            }
            field(label: "Branch") {
                GFTextField(placeholder: "main", text: $branch)
            }
            HStack {
                Text("SSH key found · ed25519 · m@velez.dev")
                    .font(AppFont.mono(11, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg3)
                Spacer()
                GFButton(title: "Clone", style: .primary) {
                    onClone(sourceURL, localPath, branch)
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
                    GFButton(title: "Open", size: .small) { onOpenRepo(repo) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).fill(theme.palette.bg1))
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.md).stroke(theme.palette.line, lineWidth: 1))
            }
        }
    }

    private func orgName(_ repo: Repository) -> String { repo.url.deletingLastPathComponent().lastPathComponent }
    private func orgInitial(_ repo: Repository) -> String { String(orgName(repo).prefix(1)) }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    CloneView(repositories: Repository.previewSamples,
              onClone: { _, _, _ in },
              onPickPath: {},
              onOpenRepo: { _ in })
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
