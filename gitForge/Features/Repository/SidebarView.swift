import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List {
            Section("Repositories") {
                ForEach(appState.repositories) { repo in
                    SidebarRow(repository: repo)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("gitForge")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await appState.presentOpenRepositoryPanel() }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Open Repository (⌘O)")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task {
                do {
                    try await appState.openRepository(at: url)
                } catch {
                    appState.presentedError = PresentedError(error: error)
                }
            }
            return true
        }
    }
}

private struct SidebarRow: View {
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
