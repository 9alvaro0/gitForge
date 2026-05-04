import SwiftUI

struct SidebarStashRow: View {
    let stash: Stash
    @Bindable var viewModel: RepositoryViewModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(stash.subject)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(stash.reference)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Task { await viewModel.revealCommit(sha: stash.sha) }
        }
        .contextMenu {
            Button("Apply") {
                Task { await viewModel.applyStash(stash, drop: false) }
            }
            Button("Pop (apply and drop)") {
                Task { await viewModel.applyStash(stash, drop: true) }
            }
            Divider()
            Button("Drop", role: .destructive) {
                Task { await viewModel.dropStash(stash) }
            }
        }
    }
}
