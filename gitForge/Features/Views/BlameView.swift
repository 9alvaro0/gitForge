import SwiftUI

/// `.gf-view-blame` — file blame view (mock data; integrates with cli later).
struct BlameView: View {
    let file: String
    let groups: [BlameGroup]

    @Environment(\.appTheme) private var theme

    init(file: String = "src/lib/lane-layout.ts",
         groups: [BlameGroup] = BlameGroup.previewSamples) {
        self.file = file
        self.groups = groups
    }

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(title: "Blame") {
                MonoText(file, dim: true)
            } right: {
                ToolButton(.arrowU, label: "Prev rev") { }
                ToolButton(.arrowD, label: "Next rev") { }
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(groups) { g in
                        BlameGroupView(group: g)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.palette.bg2)
    }
}

#Preview {
    @Previewable @State var theme = AppTheme()
    BlameView()
        .frame(width: 980, height: 620)
        .appTheme(theme)
}

private struct BlameGroupView: View {
    let group: BlameGroup
    @Environment(\.appTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top, spacing: 8) {
                    Avatar(name: group.author, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.author)
                            .font(AppFont.sans(12, weight: .medium))
                            .foregroundStyle(theme.palette.fg1)
                        Text("\(group.sha) · \(group.when)")
                            .font(AppFont.mono(11, family: theme.monoFont))
                            .foregroundStyle(theme.palette.fg3)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(width: 200, alignment: .leading)
            .background(theme.palette.bg1)
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.palette.line).frame(width: 1)
            }

            ZStack(alignment: .leading) {
                Rectangle().fill(Color(hex: group.laneColorHex).opacity(0.7)).frame(width: 2)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(group.lines) { line in
                        HStack(spacing: 0) {
                            Text("\(line.number)")
                                .font(AppFont.mono(11, family: theme.monoFont))
                                .foregroundStyle(theme.palette.fg4)
                                .frame(width: 36, alignment: .trailing)
                                .padding(.trailing, 12)
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(AppFont.mono(theme.density.monoFontSize, family: theme.monoFont))
                                .foregroundStyle(theme.palette.fg1)
                        }
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.palette.line).frame(height: 1)
        }
    }
}
