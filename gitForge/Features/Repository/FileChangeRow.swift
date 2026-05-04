import SwiftUI

struct FileChangeRow: View {
    let file: WorkingCopyFile
    let isStagedSection: Bool
    let onPrimary: () -> Void
    let onDiscard: () -> Void

    private var displayedStatus: WorkingCopyFile.Status {
        isStagedSection ? file.stagedStatus : file.unstagedStatus
    }

    private var statusColor: Color {
        switch displayedStatus {
        case .added: .green
        case .modified: .yellow
        case .deleted: .red
        case .renamed, .copied: .blue
        case .untracked: .accentColor
        case .unmerged: .orange
        case .typeChanged, .ignored, .unmodified: .gray
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(displayedStatus.displayLetter)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(statusColor, in: RoundedRectangle(cornerRadius: 4))

            Text(file.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                onPrimary()
            } label: {
                Image(systemName: isStagedSection ? "minus.circle" : "plus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .help(isStagedSection ? "Unstage" : "Stage")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contextMenu {
            if !isStagedSection {
                Button("Discard Changes...", role: .destructive) {
                    onDiscard()
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        FileChangeRow(file: WorkingCopyStatus.preview.files[0], isStagedSection: true, onPrimary: {}, onDiscard: {})
        Divider()
        FileChangeRow(file: WorkingCopyStatus.preview.files[2], isStagedSection: false, onPrimary: {}, onDiscard: {})
    }
    .frame(width: 480)
    .padding()
}
