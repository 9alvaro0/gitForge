import SwiftUI

/// `.gf-view-branches` — local + remote + tags listing.
struct BranchesView: View {
    let localBranches: [GitRef]
    let remoteBranches: [GitRef]
    let tags: [GitRef]
    let currentBranchName: String?
    var onCheckout: (GitRef) -> Void = { _ in }
    var onNewBranch: () -> Void = {}

    @State private var filter: String = ""
    @Environment(\.appTheme) private var theme

    private var filteredLocal: [GitRef]   { localBranches.filter   { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) } }
    private var filteredRemote: [GitRef]  { remoteBranches.filter  { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) } }
    private var filteredTags: [GitRef]    { tags.filter            { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) } }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Branches") {
                EmptyView()
            } right: {
                GFTextField(placeholder: "Filter branches…", text: $filter)
                    .frame(width: 220)
                ToolButton(.plus, label: "New branch", primary: true, action: onNewBranch)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    BranchSection(title: "Local", refs: filteredLocal, currentBranchName: currentBranchName, onCheckout: onCheckout)
                    BranchSection(title: "Remote", refs: filteredRemote, currentBranchName: nil, onCheckout: onCheckout)
                    if !filteredTags.isEmpty {
                        TagsSection(tags: filteredTags)
                    }
                }
                .padding(18)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }
}

private struct BranchSection: View {
    let title: String
    let refs: [GitRef]
    let currentBranchName: String?
    let onCheckout: (GitRef) -> Void

    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(theme.palette.fg3)
                Text("\(refs.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.palette.fg3)
            }
            if refs.isEmpty {
                Text("No branches.")
                    .font(AppFont.sans(12))
                    .foregroundStyle(theme.palette.fg3)
            } else {
                tableHeader
                ForEach(refs) { ref in
                    row(for: ref)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).fill(theme.palette.bg1))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg).stroke(theme.palette.line, lineWidth: 1))
    }

    private var tableHeader: some View {
        HStack {
            Spacer().frame(width: 14)
            Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
            Text("LAST COMMIT").frame(width: 120, alignment: .leading)
            Text("SYNC").frame(width: 120, alignment: .leading)
            Spacer().frame(width: 130)
        }
        .font(AppFont.mono(10.5, family: theme.monoFont))
        .tracking(0.6)
        .foregroundStyle(theme.palette.fg3)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.palette.bg2)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }

    @ViewBuilder
    private func row(for ref: GitRef) -> some View {
        let isCurrent = (ref.name == currentBranchName) && ref.isLocalBranch
        HStack(spacing: 6) {
            if isCurrent {
                Circle().fill(theme.palette.accent).frame(width: 6, height: 6)
            } else {
                Color.clear.frame(width: 6, height: 6)
            }
            HStack(spacing: 6) {
                GFIcon(kind: .branch, size: 12, stroke: theme.palette.fg2)
                Text(ref.name)
                    .font(AppFont.mono(12, family: theme.monoFont))
                    .foregroundStyle(theme.palette.fg1)
                if isCurrent {
                    Pill(text: "HEAD", kind: .clean)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("—")
                .font(AppFont.mono(12, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg3)
                .frame(width: 120, alignment: .leading)
            StatusPills(ahead: 0, behind: 0, dirty: 0)
                .frame(width: 120, alignment: .leading)
            HStack(spacing: 4) {
                if !isCurrent && ref.isLocalBranch {
                    GFButton(title: "Checkout", size: .small) { onCheckout(ref) }
                }
                IconButton(.more, action: {})
            }
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isCurrent ? theme.palette.accent.opacity(0.06) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.palette.line).frame(height: 1) }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BranchesView(
        localBranches: GitRef.previewSamples.filter(\.isLocalBranch),
        remoteBranches: GitRef.previewSamples.filter(\.isRemoteBranch),
        tags: GitRef.previewSamples.filter(\.isTag),
        currentBranchName: "main",
        onCheckout: { _ in },
        onNewBranch: {}
    )
    .frame(width: 980, height: 620)
    .appTheme(theme)
}

private struct TagsSection: View {
    let tags: [GitRef]
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAGS")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(theme.palette.fg3)
            FlowLayout(spacing: 6) {
                ForEach(tags) { tag in
                    HStack(spacing: 5) {
                        GFIcon(kind: .diamond, size: 10, stroke: theme.palette.mod)
                        Text(tag.name)
                            .font(AppFont.mono(11.5, family: theme.monoFont))
                    }
                    .foregroundStyle(theme.palette.mod)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.palette.mod.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.palette.mod.opacity(0.25), lineWidth: 1))
                }
            }
        }
    }
}
