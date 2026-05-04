import SwiftUI

struct WelcomeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 56))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                Text("gitForge")
                    .font(.system(size: 32, weight: .bold))
                Text("A modern macOS Git client")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await appState.presentOpenRepositoryPanel() }
            } label: {
                Label("Open Repository...", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if !appState.repositories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("RECENT")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    ForEach(appState.repositories.prefix(5)) { repo in
                        RecentRow(repository: repo)
                    }
                }
                .frame(maxWidth: 420)
                .padding(.top, 12)
            }

            Text("Or drop a folder anywhere in this window to open it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dropDestination(for: URL.self) { urls, _ in
            handleDrop(urls)
            return true
        }
    }

    private func handleDrop(_ urls: [URL]) {
        guard let url = urls.first else { return }
        Task {
            do {
                try await appState.openRepository(at: url)
            } catch {
                appState.presentedError = PresentedError(error: error)
            }
        }
    }
}

private struct RecentRow: View {
    let repository: Repository
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    var body: some View {
        Button {
            Task { await appState.activate(repository) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(repository.name)
                        .fontWeight(.medium)
                    Text(repository.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovering ? Color.gray.opacity(0.12) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Remove from Recents", role: .destructive) {
                Task { await appState.removeFromRecents(repository.url) }
            }
        }
    }
}

#Preview {
    WelcomeView()
        .environment(AppState())
        .frame(width: 720, height: 560)
}
