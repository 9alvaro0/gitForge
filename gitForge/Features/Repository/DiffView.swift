import SwiftUI

struct DiffView: View {
    let hunks: [DiffHunk]
    var isLoading: Bool = false
    var emptyMessage: String = "Select a file to see its diff"

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if hunks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(hunks) { hunk in
                            HunkView(hunk: hunk)
                        }
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}

private struct HunkView: View {
    let hunk: DiffHunk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@ \(hunk.header)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.10))
            ForEach(hunk.lines) { line in
                DiffLineView(line: line)
            }
        }
    }
}

private struct DiffLineView: View {
    let line: DiffLine

    private var background: Color {
        switch line.kind {
        case .added: Color.green.opacity(0.18)
        case .removed: Color.red.opacity(0.18)
        case .context, .noNewline: Color.clear
        }
    }

    private var prefix: String {
        switch line.kind {
        case .added: "+"
        case .removed: "-"
        case .context: " "
        case .noNewline: "\\"
        }
    }

    private var prefixColor: Color {
        switch line.kind {
        case .added: .green
        case .removed: .red
        default: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(line.oldLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.tertiary)
            Text(line.newLineNumber.map(String.init) ?? "")
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(.tertiary)
                .padding(.leading, 4)
                .padding(.trailing, 8)
            Text(prefix)
                .foregroundStyle(prefixColor)
                .frame(width: 14, alignment: .center)
            Text(line.content)
                .textSelection(.enabled)
            Spacer(minLength: 24)
        }
        .font(.system(.caption, design: .monospaced))
        .padding(.vertical, 1)
        .background(background)
    }
}

#Preview {
    DiffView(hunks: DiffHunk.previewSamples)
        .frame(width: 640, height: 480)
}

#Preview("Empty") {
    DiffView(hunks: [], emptyMessage: "Select a file")
        .frame(width: 480, height: 320)
}
