import SwiftUI

/// Left column of the resolver: overall progress, then every conflicted file.
struct ConflictFilesColumn: View {
    @Bindable var viewModel: RepositoryViewModel

    @Environment(\.appTheme) private var theme

    static let width: CGFloat = 280

    private var files: [ConflictFile] { viewModel.conflicts.files }
    private var resolvedCount: Int { files.filter(\.resolved).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if files.isEmpty {
                Text("No conflicted files.")
                    .textRole(.callout)
                    .foregroundStyle(theme.colors.textTertiary)
                    .padding(Spacing.s12)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.s2) {
                        ForEach(files) { file in
                            ConflictFileRow(
                                file: file,
                                isSelected: file.path == viewModel.conflicts.selectedPath,
                                absoluteURL: viewModel.repository.url.appendingPathComponent(file.path),
                                onSelect: { Task { await viewModel.conflicts.loadHunks(for: file.path) } },
                                onResolveOurs: { Task { await viewModel.resolveFile(at: file.path, using: .ours) } },
                                onResolveTheirs: { Task { await viewModel.resolveFile(at: file.path, using: .theirs) } },
                                onDiscard: { Task { await viewModel.discardChanges(workingCopyFile(for: file)) } }
                            )
                        }
                    }
                    .padding(Spacing.s6)
                }
            }
        }
        .frame(width: Self.width)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s6) {
            HStack {
                Text("Conflicted files")
                    .textRole(.caption, weight: .semibold)
                    .foregroundStyle(theme.colors.textQuaternary)
                Spacer(minLength: 0)
                Text("\(resolvedCount) of \(files.count) resolved")
                    .textRole(.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }
            ConflictProgressBar(done: resolvedCount, total: files.count)
        }
        .padding(.horizontal, Spacing.s12)
        .padding(.top, Spacing.s12)
        .padding(.bottom, Spacing.s6)
        .accessibilityElement(children: .combine)
    }

    /// Bridges to `[WorkingCopyFile]` so the unmerged-aware discard path on
    /// the view-model can be reused.
    private func workingCopyFile(for file: ConflictFile) -> [WorkingCopyFile] {
        guard let match = viewModel.status.files.first(where: { $0.path == file.path }) else {
            return []
        }
        return [match]
    }
}

/// Thin capsule bar in `ok`; the text next to it carries the numbers.
struct ConflictProgressBar: View {
    let done: Int
    let total: Int
    var width: CGFloat? = nil

    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.colors.fillControl)
                Capsule()
                    .fill(theme.colors.ok)
                    .frame(width: total > 0 ? geo.size.width * CGFloat(done) / CGFloat(total) : 0)
            }
        }
        .frame(width: width, height: 6)
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    ConflictFilesColumn(viewModel: .previewWithConflicts)
        .frame(height: 480)
        .background(theme.colors.bgContent)
        .appTheme(theme)
}
