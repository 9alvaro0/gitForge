import SwiftUI

/// A repo's heading in the inbox: its path, and "Not cloned" when it isn't on
/// this Mac. Pinned while its rows scroll under it.
struct ReviewGroupHeader: View {
    let repo: ReviewRepo

    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(spacing: Spacing.s6) {
            Text(verbatim: repo.host.slug)
                .textRole(.callout, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                // A nested GitLab path keeps both ends: group and repo.
                .truncationMode(.middle)
            if repo.localURL == nil {
                Text("Not cloned")
                    .textRole(.caption, weight: .semibold)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(.horizontal, Spacing.s6)
                    .frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: Radius.badge).fill(theme.colors.fillControl))
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.s12)
        // Closer to its own rows than to the group above.
        .padding(.top, Spacing.s12)
        .padding(.bottom, Spacing.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.bgContent)
        .help(Text(verbatim: "\(repo.host.host)/\(repo.host.slug)"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    let instance = HostingInstance(kind: .gitlab, host: "gitlab.example.test")
    VStack(spacing: 0) {
        ForEach(["apps/payments/android/payments-app", "apps/platform/infra-modules"], id: \.self) { path in
            ReviewGroupHeader(repo: ReviewRepo(host: RemoteHost.make(fullName: path, on: instance)!,
                                               accountId: UUID(), sources: [.activity], lastActivity: nil,
                                               cloneURL: "https://gitlab.example.test/\(path).git",
                                               localURL: path.hasSuffix("-app") ? URL(fileURLWithPath: "/tmp/payments-app") : nil))
        }
    }
    .frame(width: 320)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
