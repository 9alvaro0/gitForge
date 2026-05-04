import SwiftUI

struct SidebarBranchRow: View {
    let ref: GitRef
    let leafName: String
    @Bindable var viewModel: RepositoryViewModel
    let onCheckout: () -> Void
    let onRename: (() -> Void)?
    let onDelete: (() -> Void)?

    private var isCurrent: Bool {
        ref.isLocalBranch && viewModel.currentBranchName == ref.name
    }

    private var iconName: String {
        switch ref.kind {
        case .localBranch: "point.topleft.down.to.point.bottomright.curvepath"
        case .remoteBranch: "arrow.triangle.branch"
        case .tag: "tag"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            Text(leafName)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.tail)
            if isCurrent {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await viewModel.revealCommit(sha: ref.targetSha) }
        }
        .onTapGesture(count: 2) {
            if !isCurrent { onCheckout() }
        }
        .contextMenu {
            if !isCurrent {
                Button("Checkout", action: onCheckout)
            }
            if let onRename {
                Button("Rename...", action: onRename)
            }
            if let onDelete, !isCurrent {
                Divider()
                Button("Delete...", role: .destructive, action: onDelete)
            }
        }
    }
}
