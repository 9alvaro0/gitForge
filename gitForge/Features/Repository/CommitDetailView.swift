import SwiftUI

struct CommitDetailView: View {
    let commit: Commit
    @Bindable var viewModel: RepositoryViewModel
    @State private var detail: CommitDetail?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metadata
                Divider()
                if let detail, !detail.bodyText.isEmpty {
                    bodyMessage(detail.bodyText)
                    Divider()
                }
                fileList
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: commit.id) {
            detail = await viewModel.detail(for: commit)
        }
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(commit.subject)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            HStack(spacing: 12) {
                Label(commit.shortSha, systemImage: "number")
                    .font(.system(.caption, design: .monospaced))
                Label(commit.authorName, systemImage: "person")
                Label(Self.dateFormatter.string(from: commit.authorDate), systemImage: "calendar")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if !commit.parentShas.isEmpty {
                HStack(spacing: 6) {
                    Text("Parents:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(commit.parentShas, id: \.self) { parent in
                        Text(String(parent.prefix(7)))
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
    }

    private func bodyMessage(_ body: String) -> some View {
        Text(body)
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files (\(detail?.files.count ?? 0))")
                .font(.headline)
            if let detail {
                if detail.files.isEmpty {
                    Text("No file changes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(detail.files) { file in
                        HStack(spacing: 8) {
                            statusBadge(file.status)
                            Text(file.path)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                        }
                    }
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func statusBadge(_ status: CommitFileChange.Status) -> some View {
        let color: Color = switch status {
        case .added: .green
        case .modified: .yellow
        case .deleted: .red
        case .renamed, .copied: .blue
        case .typeChanged, .unmerged, .unknown: .gray
        }
        return Text(status.displayLetter)
            .font(.system(.caption2, design: .monospaced).weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
    }
}

#Preview {
    CommitDetailView(commit: Commit.preview, viewModel: RepositoryViewModel.preview)
        .frame(width: 520, height: 540)
}
