import SwiftUI

/// `.gf-view-terminal` — readonly visual terminal echoing the design's mock output.
struct TerminalView: View {
    let workingDirectory: String

    @Environment(\.appTheme) private var theme

    private let staticLines: [TermLine] = [
        .cmd("git status"),
        .out("On branch feat/commit-graph"),
        .out("Your branch is ahead of origin/feat/commit-graph by 7 commits."),
        .out(""),
        .out("Changes to be committed:"),
        .out("  modified:   src/components/CommitGraph.tsx"),
        .out("  modified:   src/store/commitStore.ts"),
        .out("  new file:   src/lib/lane-layout.ts"),
        .out(""),
        .cmd("git log --oneline -5"),
        .out("8b1d99e fix: scroll restoration on branch switch"),
        .out("2c7e4b0 Tighten lane spacing for dense histories"),
        .out("fe33a02 Merge branch 'main' into feat/commit-graph"),
        .out("d91c8aa Bump react to 18.3.1"),
        .out("7e2a155 docs: add CONTRIBUTING.md and CODEOWNERS"),
        .prompt,
    ]

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Terminal") {
                MonoText("zsh · \(workingDirectory)", dim: true)
            } right: {
                EmptyView()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(staticLines.enumerated()), id: \.offset) { idx, line in
                        renderLine(line, isLast: idx == staticLines.count - 1)
                    }
                }
                .padding(20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }

    @ViewBuilder
    private func renderLine(_ line: TermLine, isLast: Bool) -> some View {
        switch line {
        case .cmd(let text):
            HStack(spacing: 8) {
                Text(workingDirectory)
                    .foregroundStyle(theme.palette.accent)
                Text("›").foregroundStyle(theme.palette.fg3)
                Text(text).foregroundStyle(theme.palette.fg1)
            }
            .font(AppFont.mono(13, family: theme.monoFont))
        case .out(let text):
            Text(text.isEmpty ? " " : text)
                .font(AppFont.mono(13, family: theme.monoFont))
                .foregroundStyle(theme.palette.fg2)
        case .prompt:
            HStack(spacing: 8) {
                Text(workingDirectory).foregroundStyle(theme.palette.accent)
                Text("›").foregroundStyle(theme.palette.fg3)
                if isLast { BlinkingCursor() }
            }
            .font(AppFont.mono(13, family: theme.monoFont))
        }
    }

    enum TermLine {
        case cmd(String)
        case out(String)
        case prompt
    }
}

private struct BlinkingCursor: View {
    @Environment(\.appTheme) private var theme
    @State private var visible = true
    var body: some View {
        Rectangle().fill(theme.palette.accent).frame(width: 7, height: 14)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever()) { visible = false }
            }
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    TerminalView(workingDirectory: "~/code/gitforge")
        .frame(width: 980, height: 620)
        .appTheme(theme)
}
