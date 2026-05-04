import SwiftUI

struct SidebarRepositoryRow: View {
    let repository: Repository
    @Environment(AppState.self) private var appState

    private var isActive: Bool {
        appState.activeRepository?.url == repository.url
    }

    var body: some View {
        Button {
            Task { await appState.activate(repository) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "folder.fill" : "folder")
                    .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                VStack(alignment: .leading, spacing: 1) {
                    Text(repository.name)
                        .fontWeight(isActive ? .semibold : .regular)
                    Text(repository.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                Task { await appState.removeFromRecents(repository.url) }
            }
        }
    }
}
