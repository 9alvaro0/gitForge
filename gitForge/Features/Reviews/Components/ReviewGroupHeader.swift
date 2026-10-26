import SwiftUI

/// A repo's heading in Team and Mine: its path, and "Not cloned" when it isn't
/// on this Mac. Pinned while its rows scroll under it. The open repository's
/// looks like any other, first in the list. A followed repo's, and the open
/// repository's when it isn't followed, has "Hide" in its context menu (R3
/// Ruling 15, U1 Ruling 8).
struct ReviewGroupHeader: View {
    let repo: ReviewRepo
    /// Hides the repo from Team and Mine; `nil` offers nothing (a repo opened
    /// from a search, which nobody follows).
    var onHide: (() -> Void)? = nil

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
        .reviewSectionHeader()
        .help(Text(verbatim: "\(repo.host.host)/\(repo.host.slug)"))
        .modifier(HideMenu(onHide: onHide))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The hiding as the context menu, only with `onHide`: without it there's
    /// no menu at all, rather than an empty one.
    private struct HideMenu: ViewModifier {
        let onHide: (() -> Void)?

        func body(content: Content) -> some View {
            if let onHide {
                content.contextMenu { Button(String(localized: "Hide from Reviews"), action: onHide) }
            } else {
                content
            }
        }
    }
}

/// The heading over the pull requests opened from a link that aren't rows of
/// the followed repos (R2 Ruling 9), with a repo's heading's look.
struct ReviewOthersHeader: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        Text("Others")
            .textRole(.callout, weight: .semibold)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(1)
            .reviewSectionHeader()
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// What every heading of the inbox shares: its inset, a little closer
    /// to its own rows than to the group above, and the list's background,
    /// so the rows scroll under it while it's pinned.
    func reviewSectionHeader() -> some View {
        modifier(ReviewSectionHeaderChrome())
    }
}

private struct ReviewSectionHeaderChrome: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.s12)
            .padding(.top, Spacing.s12)
            .padding(.bottom, Spacing.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.colors.bgContent)
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
                                               localURL: path.hasSuffix("-app") ? URL(fileURLWithPath: "/tmp/payments-app") : nil),
                              onHide: {})
        }
    }
    .frame(width: 320)
    .background(theme.colors.bgContent)
    .appTheme(theme)
}
